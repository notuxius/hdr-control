using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;

namespace LocalHdrMenu {
    public sealed class TrayPopupMenu : ContextMenuStrip {
        Padding surfacePadding = new Padding(6);
        protected override Padding DefaultPadding { get { return surfacePadding; } }
        public void SetSurfacePadding(Padding value) { surfacePadding = value; Padding = value; }
    }
    public sealed class TrayStatusItem : ToolStripMenuItem {
        public override bool CanSelect { get { return false; } }
    }
    // Keep native ToolStrip menus for keyboard navigation and tray dismissal.
    public sealed class TrayMenuRenderer : ToolStripProfessionalRenderer {
        static readonly Color Surface = Color.FromArgb(32, 34, 39);
        static readonly Color Hover = Color.FromArgb(51, 55, 63);
        static readonly Color Border = Color.FromArgb(67, 72, 81);
        static readonly Color Text = Color.FromArgb(239, 242, 247);
        static readonly Color Muted = Color.FromArgb(164, 174, 189);
        static readonly Color Accent = Color.FromArgb(137, 194, 255);
        public TrayMenuRenderer() { RoundedEdges = false; }
        static bool Contrast { get { return SystemInformation.HighContrast; } }
        static int Px(Graphics g, float value) { return Math.Max(1, (int)Math.Round(value * g.DpiX / 96)); }
        public static GraphicsPath Round(Rectangle r, int radius) {
            var path = new GraphicsPath();
            int d = Math.Min(radius * 2, Math.Min(r.Width, r.Height));
            if (d < 2) { path.AddRectangle(r); return path; }
            path.AddArc(r.Left, r.Top, d, d, 180, 90);
            path.AddArc(r.Right-d, r.Top, d, d, 270, 90);
            path.AddArc(r.Right-d, r.Bottom-d, d, d, 0, 90);
            path.AddArc(r.Left, r.Bottom-d, d, d, 90, 90);
            path.CloseFigure();
            return path;
        }
        protected override void OnRenderToolStripBackground(ToolStripRenderEventArgs e) {
            e.Graphics.Clear(Contrast ? SystemColors.Menu : Surface);
        }
        protected override void OnRenderImageMargin(ToolStripRenderEventArgs e) { }
        void ClearRow(ToolStripItemRenderEventArgs e) {
            using (var brush = new SolidBrush(Contrast ? SystemColors.Menu : Surface)) {
                e.Graphics.FillRectangle(brush, new Rectangle(Point.Empty, e.Item.Size));
            }
        }
        protected override void OnRenderMenuItemBackground(ToolStripItemRenderEventArgs e) {
            // Repaint unselected rows too, removing any previous hover fill.
            ClearRow(e);
            if (!e.Item.Enabled || !e.Item.Selected) return;
            int inset = Px(e.Graphics, 6);
            var bounds = new Rectangle(inset, 1, e.Item.Width-inset*2, e.Item.Height-2);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var path = Round(bounds, Px(e.Graphics, 5)))
            using (var brush = new SolidBrush(Contrast ? SystemColors.Highlight : Hover)) {
                e.Graphics.FillPath(brush, path);
            }
        }
        protected override void OnRenderItemText(ToolStripItemTextRenderEventArgs e) {
            if (Contrast) e.TextColor = !e.Item.Enabled ? SystemColors.GrayText : e.Item.Selected ? SystemColors.HighlightText : SystemColors.MenuText;
            else e.TextColor = !e.Item.Enabled ? Muted : e.Item.Name == "HdrAction" ? Accent : Text;
            // The stock text rectangle is based on the compact native row
            // metrics, not our taller rows. Center against the actual row.
            int inset = Px(e.Graphics, 18);
            var submenu = e.Item as ToolStripDropDownItem;
            int arrowSpace = submenu != null && submenu.HasDropDownItems ? Px(e.Graphics, 14) : 0;
            var bounds = new Rectangle(inset, 0, Math.Max(1, e.Item.Width-inset*2-arrowSpace), e.Item.Height);
            TextRenderer.DrawText(e.Graphics, e.Text, e.TextFont, bounds, e.TextColor,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine |
                TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis);
        }
        protected override void OnRenderSeparator(ToolStripSeparatorRenderEventArgs e) {
            int inset = Px(e.Graphics, 12);
            using (var pen = new Pen(Contrast ? SystemColors.GrayText : Border)) {
                e.Graphics.DrawLine(pen, inset, e.Item.Height/2, e.Item.Width-inset, e.Item.Height/2);
            }
        }
        protected override void OnRenderArrow(ToolStripArrowRenderEventArgs e) {
            Color color = Contrast ? (e.Item.Selected ? SystemColors.HighlightText : SystemColors.MenuText) : Muted;
            int x = e.Direction == ArrowDirection.Left ? Px(e.Graphics, 14) : e.Item.Width-Px(e.Graphics, 14);
            int y = e.Item.Height/2;
            int delta = Px(e.Graphics, 3);
            int tip = e.Direction == ArrowDirection.Left ? -delta : delta;
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var pen = new Pen(color, Math.Max(1, e.Graphics.DpiX/96))) {
                e.Graphics.DrawLines(pen, new Point[] { new Point(x,y-delta), new Point(x+tip,y), new Point(x,y+delta) });
            }
        }
        protected override void OnRenderToolStripBorder(ToolStripRenderEventArgs e) {
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            using (var path = Round(new Rectangle(0, 0, e.ToolStrip.Width-1, e.ToolStrip.Height-1), Px(e.Graphics, 8)))
            using (var pen = new Pen(Contrast ? SystemColors.WindowText : Border)) {
                e.Graphics.DrawPath(pen, path);
            }
        }
    }

    public static class TrayMenuTheme {
        public static void Apply(ToolStripDropDown menu, Font font) {
            float scale;
            using (var g = menu.CreateGraphics()) { scale = g.DpiX / 96f; }
            int edge = (int)Math.Round(6 * scale);
            menu.Renderer = new TrayMenuRenderer();
            menu.Font = font;
            menu.BackColor = SystemInformation.HighContrast ? SystemColors.Menu : Color.FromArgb(32, 34, 39);
            menu.ForeColor = SystemColors.MenuText;
            menu.MinimumSize = new Size((int)Math.Round(240 * scale), 0);
            var dropdown = menu as ToolStripDropDownMenu;
            if (dropdown != null) { dropdown.ShowImageMargin = false; dropdown.ShowCheckMargin = false; }
            // Native menu layout recalculates narrow item widths when a popup
            // opens. A vertical flow preserves equal full-width rows instead.
            menu.LayoutStyle = ToolStripLayoutStyle.Flow;
            menu.AutoSize = false;
            var flow = (FlowLayoutSettings)menu.LayoutSettings;
            flow.FlowDirection = FlowDirection.TopDown;
            flow.WrapContents = false;
            var popup = menu as TrayPopupMenu;
            if (popup != null) popup.SetSurfacePadding(new Padding(edge));
            else menu.Padding = new Padding(edge);
            bool layingOut = false;
            menu.Layout += delegate {
                if (layingOut) return;
                layingOut = true;
                try {
                    int width = (int)Math.Round(240 * scale);
                    foreach (ToolStripItem item in menu.Items) {
                        if (!(item is ToolStripSeparator)) {
                            width = Math.Max(width, TextRenderer.MeasureText(item.Text, item.Font).Width + edge*10);
                        }
                    }
                    menu.MinimumSize = new Size(width, 0);
                    int totalHeight = menu.Padding.Vertical;
                    foreach (ToolStripItem item in menu.Items) {
                        int height = item is ToolStripSeparator ? edge*2 : Math.Max((int)Math.Round(34*scale), item.Font.Height + (int)Math.Round(16*scale));
                        item.Padding = Padding.Empty;
                        item.Margin = Padding.Empty;
                        item.AutoSize = false;
                        // ToolStripMenuItem anchors at x=0 even with popup
                        // padding; reserve the horizontal inset in rendering.
                        item.Size = new Size(width, height);
                        if (item.Available) totalHeight += height;
                    }
                    menu.Size = new Size(width, totalHeight);
                } finally { layingOut = false; }
            };
            menu.SizeChanged += delegate {
                Region old = menu.Region;
                using (var path = TrayMenuRenderer.Round(new Rectangle(0, 0, menu.Width, menu.Height), (int)Math.Round(8*scale))) {
                    menu.Region = SystemInformation.HighContrast ? null : new Region(path);
                }
                if (old != null) old.Dispose();
            };
            menu.PerformLayout();
        }
    }
}
