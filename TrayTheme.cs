using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace LocalHdrMenu {
    public static class TrayIconPosition {
        // https://learn.microsoft.com/windows/win32/api/shellapi/nf-shellapi-shell_notifyicongetrect
        // Windows PowerShell uses .NET Framework's HWND + numeric NotifyIcon ID.
        [StructLayout(LayoutKind.Sequential)]
        struct Identifier { public uint Size; public IntPtr Window; public uint Id; public Guid Guid; }
        [StructLayout(LayoutKind.Sequential)]
        struct NativeRect { public int Left, Top, Right, Bottom; }
        [DllImport("shell32.dll")]
        static extern int Shell_NotifyIconGetRect(ref Identifier identifier, out NativeRect bounds);
        static readonly FieldInfo WindowField = typeof(NotifyIcon).GetField("window", BindingFlags.Instance | BindingFlags.NonPublic);
        static readonly FieldInfo IdField = typeof(NotifyIcon).GetField("id", BindingFlags.Instance | BindingFlags.NonPublic);
        public static bool TryGetBounds(NotifyIcon icon, out Rectangle bounds) {
            bounds = Rectangle.Empty;
            if (icon == null || !icon.Visible || WindowField == null || IdField == null) return false;
            var window = WindowField.GetValue(icon) as NativeWindow;
            if (window == null || window.Handle == IntPtr.Zero) return false;
            var identifier = new Identifier {
                Size = (uint)Marshal.SizeOf(typeof(Identifier)), Window = window.Handle,
                Id = unchecked((uint)(int)IdField.GetValue(icon)), Guid = Guid.Empty
            };
            NativeRect rect;
            if (Shell_NotifyIconGetRect(ref identifier, out rect) != 0 || rect.Right <= rect.Left || rect.Bottom <= rect.Top) return false;
            bounds = Rectangle.FromLTRB(rect.Left, rect.Top, rect.Right, rect.Bottom);
            return true;
        }
    }
    public sealed class TrayPopupMenu : ContextMenuStrip {
        Padding surfacePadding = new Padding(6);
        Point popupAnchor;
        public NotifyIcon AnchorIcon { get; set; }
        public bool ShowActionIcons { get; set; }
        protected override Padding DefaultPadding { get { return surfacePadding; } }
        public void SetSurfacePadding(Padding value) { surfacePadding = value; Padding = value; }
        public static Point CenteredLocation(Point anchor, Size size, Rectangle workArea, int gap) {
            int x = anchor.X - size.Width / 2;
            int y = anchor.Y - size.Height - gap;
            return new Point(
                Math.Max(workArea.Left, Math.Min(x, workArea.Right - size.Width)),
                Math.Max(workArea.Top, Math.Min(y, workArea.Bottom - size.Height)));
        }
        protected override void OnOpening(System.ComponentModel.CancelEventArgs e) {
            popupAnchor = Cursor.Position;
            Rectangle iconBounds;
            if (TrayIconPosition.TryGetBounds(AnchorIcon, out iconBounds))
                popupAnchor = new Point(iconBounds.Left + iconBounds.Width / 2, iconBounds.Top);
            base.OnOpening(e);
        }
        protected override void OnOpened(EventArgs e) {
            // NotifyIcon still owns focus and dismissal. Reposition only the
            // root popup after native placement and final menu layout.
            if (AnchorIcon != null) {
                int gap;
                using (var g = CreateGraphics()) { gap = (int)Math.Round(6 * g.DpiY / 96); }
                Location = CenteredLocation(popupAnchor, Size, Screen.FromPoint(popupAnchor).WorkingArea, gap);
            }
            base.OnOpened(e);
        }
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
            else e.TextColor = !e.Item.Enabled ? Muted : Text;
            // The stock text rectangle is based on the compact native row
            // metrics, not our taller rows. Center against the actual row.
            int inset = Px(e.Graphics, 18);
            var popup = e.ToolStrip as TrayPopupMenu;
            int iconSpace = popup != null && popup.ShowActionIcons ? Px(e.Graphics, 26) : 0;
            if (iconSpace > 0) DrawGlyph(e.Graphics, e.Item, inset, e.TextColor);
            var submenu = e.Item as ToolStripDropDownItem;
            int arrowSpace = submenu != null && submenu.HasDropDownItems ? Px(e.Graphics, 14) : 0;
            var bounds = new Rectangle(inset+iconSpace, 0, Math.Max(1, e.Item.Width-inset*2-arrowSpace-iconSpace), e.Item.Height);
            TextRenderer.DrawText(e.Graphics, e.Text, e.TextFont, bounds, e.TextColor,
                TextFormatFlags.Left | TextFormatFlags.VerticalCenter | TextFormatFlags.SingleLine |
                TextFormatFlags.NoPrefix | TextFormatFlags.NoPadding | TextFormatFlags.EndEllipsis);
        }
        static void DrawGlyph(Graphics g, ToolStripItem item, int left, Color color) {
            string status = item.Tag as string ?? item.Text;
            if (item.Name == "HdrAction") status = status == "On" ? "HDR: On" : "HDR: Off";
            bool highlighted = item.Enabled && item.Selected;
            Color background = Contrast ? (highlighted ? SystemColors.Highlight : SystemColors.Menu) : (highlighted ? Hover : Surface);
            if (!Contrast && (item.Name == "HdrStatus" || (item.Name == "HdrAction" && item.Enabled))) {
                if (status == "HDR: Off") color = Color.FromArgb(227, 190, 44);
                else if (status == "HDR: On") color = Color.FromArgb(68, 195, 149);
                else if (status == "HDR: Unavailable") color = Color.FromArgb(235, 126, 126);
            }
            var saved = g.Save();
            try {
                float scale = g.DpiX / 96f;
                g.TranslateTransform(left, (item.Height - 16 * scale) / 2);
                g.ScaleTransform(scale, scale);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (var pen = new Pen(color, 1.5f)) {
                    pen.StartCap = pen.EndCap = LineCap.Round;
                    pen.LineJoin = LineJoin.Round;
                    if (item.Name == "HdrSettings") {
                        // Same filled sparkles and proportions as the 24px tray artwork.
                        DrawSparkle(g,6,20f/3,16f/3,color);
                        DrawSparkle(g,12,10f/3,2,Contrast || !item.Enabled ? color : Color.White);
                        DrawSettingsGear(g, color, background, true);
                    } else if (item.Name == "DisplaySettings" || item.Name == "Displays") {
                        g.DrawRectangle(pen,1,2,14,10);
                        g.DrawLine(pen,8,12,8,15); g.DrawLine(pen,5,15,11,15);
                        if (item.Name == "DisplaySettings") DrawSettingsGear(g, color, background, true);
                    } else if (item.Name == "ExitAction") {
                        g.DrawArc(pen,2,2,12,12,-45,270); g.DrawLine(pen,8,0.5f,8,7);
                    } else if (item.Name == "HdrStatus" || item.Name == "HdrAction") {
                        g.DrawEllipse(pen,1,1,14,14);
                        if (status == "HDR: Unavailable") {
                            g.DrawLine(pen,5,5,11,11); g.DrawLine(pen,11,5,5,11);
                        } else if (status == "HDR: On") {
                            g.DrawLines(pen,new PointF[] {new PointF(4,8),new PointF(7,11),new PointF(12,5)});
                        } else if (status == "HDR: Mixed") {
                            using (var brush = new SolidBrush(color)) { g.FillPie(brush,4,4,8,8,-90,180); }
                        } else { g.DrawLine(pen,4.5f,8,11.5f,8); }
                    }
                }
            } finally { g.Restore(saved); }
        }
        static void DrawSparkle(Graphics g, float x, float y, float radius, Color color) {
            float inset = radius * .32f;
            using (var brush = new SolidBrush(color)) {
                g.FillPolygon(brush,new PointF[] {
                    new PointF(x,y-radius),new PointF(x+inset,y-inset),
                    new PointF(x+radius,y),new PointF(x+inset,y+inset),
                    new PointF(x,y+radius),new PointF(x-inset,y+inset),
                    new PointF(x-radius,y),new PointF(x-inset,y-inset)
                });
            }
        }
        static void DrawSettingsGear(Graphics g, Color color, Color background, bool clearBehind) {
            var gear = new PointF[24];
            for (int i = 0; i < gear.Length; i++) {
                double angle = i * Math.PI / 12;
                float radius = i % 4 == 1 || i % 4 == 2 ? 3.4f : 2.5f;
                gear[i] = new PointF(12.2f + radius * (float)Math.Cos(angle), 12.2f + radius * (float)Math.Sin(angle));
            }
            using (var backdrop = new SolidBrush(background))
            using (var fill = new SolidBrush(color)) {
                if (clearBehind) g.FillEllipse(backdrop,7.9f,7.9f,8.6f,8.6f);
                g.FillPolygon(fill,gear);
                g.FillEllipse(backdrop,10.95f,10.95f,2.5f,2.5f);
            }
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
                            width = Math.Max(width, TextRenderer.MeasureText(item.Text, item.Font).Width + edge*10 + (popup != null && popup.ShowActionIcons ? (int)Math.Round(26*scale) : 0));
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
