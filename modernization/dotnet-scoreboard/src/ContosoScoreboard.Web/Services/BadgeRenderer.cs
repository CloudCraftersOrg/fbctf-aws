using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Web;

namespace ContosoScoreboard.Web.Services
{
    // System.Drawing.Common is Windows-only from .NET 6 onward. Every call here
    // is a transformation target: the agent must swap to a cross-platform
    // imaging library (ImageSharp / SkiaSharp) and drop the HttpContext use.
    public static class BadgeRenderer
    {
        public static byte[] Render(string teamName, int score, int rank)
        {
            var cacheDir = HttpContext.Current.Server.MapPath("~/cache/badges");
            var cacheFile = Path.Combine(cacheDir, $"{teamName}-{score}.png");
            if (File.Exists(cacheFile))
            {
                return File.ReadAllBytes(cacheFile);
            }

            using (var bmp = new Bitmap(320, 96))
            using (var g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = SmoothingMode.AntiAlias;
                g.Clear(Color.FromArgb(24, 28, 36));
                using (var brush = new LinearGradientBrush(
                    new Rectangle(0, 0, 320, 96), Color.SlateBlue, Color.MediumPurple, 0f))
                using (var font = new Font("Segoe UI", 16, FontStyle.Bold))
                {
                    g.FillRectangle(brush, 0, 0, 320, 8);
                    g.DrawString($"#{rank}  {teamName}", font, Brushes.White, 12, 20);
                    g.DrawString($"{score} pts", new Font("Segoe UI", 12), Brushes.Gainsboro, 12, 54);
                }

                using (var ms = new MemoryStream())
                {
                    bmp.Save(ms, ImageFormat.Png);
                    var bytes = ms.ToArray();
                    File.WriteAllBytes(cacheFile, bytes);
                    return bytes;
                }
            }
        }
    }
}
