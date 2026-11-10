using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Text;

namespace DinkHelper
{
    /// <summary>
    /// Reads the data code the addon draws in the top-left corner of a screenshot.
    /// Layout (see DinkForDiscord/Strip.lua): 64 square cells per row; row 0 is
    /// red, green, blue, white, then black/white alternating; later rows hold 3 bits per cell.
    /// Bytes: 'D' 'K' version lenHi lenLo payload adler32(4, big endian).
    /// </summary>
    public static class StripDecoder
    {
        const int Cols = 64;
        const int Version = 1;

        public static string DecodeFile(string path)
        {
            using (var bmp = LoadBitmap(path))
                return bmp == null ? null : Decode(bmp);
        }

        static Bitmap LoadBitmap(string path)
        {
            try
            {
                // Copy into memory so the file isn't kept locked.
                var bytes = System.IO.File.ReadAllBytes(path);
                using (var ms = new System.IO.MemoryStream(bytes))
                using (var img = Image.FromStream(ms))
                    return new Bitmap(img);
            }
            catch { return null; }
        }

        public static string Decode(Bitmap bmp)
        {
            // Only the top-left corner matters.
            int w = Math.Min(bmp.Width, 1400), h = Math.Min(bmp.Height, 1000);
            if (w < 64 || h < 16) return null;
            var px = new Pixels(bmp, w, h);

            if (!FindOrigin(px, out int ox, out int oy)) return null;
            double cell = EstimateCell(px, ox, oy);
            if (cell < 2.5 || cell > 60) return null;
            double pitch = RefinePitch(px, ox, oy, cell, out int score);
            if (score < Cols - 3) return null;

            var bytes = new List<byte>();
            int acc = 0, nbits = 0, need = 5;
            for (int row = 1; ; row++)
            {
                if (oy + (row + 1) * pitch > h + 1) return null;
                for (int col = 0; col < Cols; col++)
                {
                    int v = px.ClassifyCell(ox + (col + 0.5) * pitch, oy + (row + 0.5) * pitch, pitch);
                    for (int b = 2; b >= 0; b--)
                    {
                        acc = (acc << 1) | ((v >> b) & 1);
                        if (++nbits == 8)
                        {
                            bytes.Add((byte)acc);
                            acc = 0; nbits = 0;
                            if (bytes.Count == 5)
                            {
                                if (bytes[0] != 0x44 || bytes[1] != 0x4B || bytes[2] != Version) return null;
                                need = 5 + (bytes[3] << 8 | bytes[4]) + 4;
                            }
                            if (bytes.Count >= need && bytes.Count > 5) return Finish(bytes, need);
                        }
                    }
                }
            }
        }

        static string Finish(List<byte> bytes, int need)
        {
            int len = need - 9;
            var body = bytes.GetRange(5, len).ToArray();
            uint sum = (uint)(bytes[5 + len] << 24 | bytes[6 + len] << 16 | bytes[7 + len] << 8 | bytes[8 + len]);
            if (Adler32(body) != sum) return null;
            return Encoding.UTF8.GetString(body);
        }

        public static uint Adler32(byte[] data)
        {
            uint a = 1, b = 0;
            foreach (var d in data) { a = (a + d) % 65521; b = (b + a) % 65521; }
            return b << 16 | a;
        }

        static bool FindOrigin(Pixels px, out int ox, out int oy)
        {
            for (int y = 0; y < 12; y++)
                for (int x = 0; x < 12; x++)
                    if (px.Color(x, y) == 4 && px.Color(x + 1, y + 1) == 4 && px.Color(x + 2, y + 2) == 4)
                    { ox = x; oy = y; return true; }
            ox = oy = 0;
            return false;
        }

        // Measures the red, green and blue finder cells along a line inside row 0.
        static double EstimateCell(Pixels px, int ox, int oy)
        {
            int y = oy + 2, x = ox;
            int[] expect = { 4, 2, 1 };
            foreach (var color in expect)
            {
                int start = x;
                while (x < px.W && px.Color(x, y) == color) x++;
                if (x == start) return 0;
                // Skip a blurry edge pixel or two between cells.
                int guard = 0;
                while (x < px.W && guard < 3 && px.Color(x, y) != NextOf(color)) { x++; guard++; }
            }
            return (x - ox) / 3.0;
        }

        static int NextOf(int color) => color == 4 ? 2 : color == 2 ? 1 : 7;

        static int Expected(int i) => i == 0 ? 4 : i == 1 ? 2 : i == 2 ? 1 : i == 3 ? 7 : (i % 2 == 0 ? 0 : 7);

        static double RefinePitch(Pixels px, int ox, int oy, double guess, out int bestScore)
        {
            double best = guess; bestScore = -1;
            for (double p = Math.Max(2, guess - 1.2); p <= guess + 1.2; p += 0.02)
            {
                if (ox + Cols * p > px.W) break;
                int score = 0;
                for (int i = 0; i < Cols; i++)
                    if (px.ClassifyCell(ox + (i + 0.5) * p, oy + 0.5 * p, p) == Expected(i)) score++;
                if (score > bestScore || (score == bestScore && Math.Abs(p - guess) < Math.Abs(best - guess)))
                { bestScore = score; best = p; }
            }
            return best;
        }

        sealed class Pixels
        {
            public readonly int W, H;
            readonly int[] data;

            public Pixels(Bitmap bmp, int w, int h)
            {
                W = w; H = h;
                data = new int[w * h];
                var lockData = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                try
                {
                    for (int y = 0; y < h; y++)
                        Marshal.Copy(lockData.Scan0 + y * lockData.Stride, data, y * w, w);
                }
                finally { bmp.UnlockBits(lockData); }
            }

            public int Color(int x, int y)
            {
                if (x < 0 || y < 0 || x >= W || y >= H) return -1;
                int c = data[y * W + x];
                return Bits((c >> 16) & 255, (c >> 8) & 255, c & 255);
            }

            static int Bits(int r, int g, int b) => (r > 127 ? 4 : 0) | (g > 127 ? 2 : 0) | (b > 127 ? 1 : 0);

            // Averages the middle of a cell and returns its 3-bit colour.
            public int ClassifyCell(double cx, double cy, double pitch)
            {
                int rad = Math.Max(0, (int)(pitch * 0.2));
                int x0 = (int)Math.Floor(cx), y0 = (int)Math.Floor(cy);
                long r = 0, g = 0, b = 0; int n = 0;
                for (int y = y0 - rad; y <= y0 + rad; y++)
                    for (int x = x0 - rad; x <= x0 + rad; x++)
                    {
                        if (x < 0 || y < 0 || x >= W || y >= H) continue;
                        int c = data[y * W + x];
                        r += (c >> 16) & 255; g += (c >> 8) & 255; b += c & 255; n++;
                    }
                if (n == 0) return -1;
                return Bits((int)(r / n), (int)(g / n), (int)(b / n));
            }
        }
    }
}
