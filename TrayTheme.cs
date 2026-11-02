using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows.Forms;

namespace LocalHdrMenu {
    public class DialogForm : Form {
        // Shared for the helper's lifetime, including the running-app picker thread.
        public static Icon ApplicationIcon { get; set; }
        readonly Icon windowIcon;
        public DialogForm() {
            DoubleBuffered=true;
            if(ApplicationIcon!=null) {
                windowIcon=(Icon)ApplicationIcon.Clone();
                Icon=windowIcon;
            }
        }
        protected override void Dispose(bool disposing) {
            base.Dispose(disposing);
            if(disposing && windowIcon!=null) windowIcon.Dispose();
        }
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr window,int attribute,ref int value,int size);
        [DllImport("user32.dll")] static extern bool RedrawWindow(IntPtr window,IntPtr rect,IntPtr region,uint flags);
        bool cloaked;
        void Cloak(bool value) {
            if(!TopLevel || !IsHandleCreated) return;
            int enabled=value?1:0;
            if(DwmSetWindowAttribute(Handle,13 /* DWMWA_CLOAK */,ref enabled,4)>=0) cloaked=value;
        }
        internal void Embed(Panel page) {
            TopLevel=false;
            FormBorderStyle=FormBorderStyle.None;
            MinimumSize=Size.Empty;
            Dock=DockStyle.Fill;
            page.Controls.Add(this);
            Show();
        }
        internal void CloseSettings() { ((Form)TopLevelControl).Close(); }
        internal const int SettingsFooterHeight=64;
        internal Panel CreateSettingsFooter() {
            var footer=new Panel {Width=ClientSize.Width,Height=SettingsFooterHeight,Dock=DockStyle.Bottom};
            var close=new DialogButton {Text="Close",Bounds=new Rectangle(footer.Width-124,12,100,38),
                Anchor=AnchorStyles.Top|AnchorStyles.Right};
            close.Click+=delegate { CloseSettings(); };
            footer.Controls.Add(close); Controls.Add(footer); CancelButton=close;
            return footer;
        }
        protected override void OnHandleCreated(EventArgs e) {
            // Hide the frame as well as the body before Windows can display either.
            Cloak(true);
            base.OnHandleCreated(e);
            if(Visible) BeginInvoke(new MethodInvoker(Reveal));
        }
        protected override void OnHandleDestroyed(EventArgs e) {
            cloaked=false;
            base.OnHandleDestroyed(e);
        }
        protected override void SetVisibleCore(bool value) {
            bool opening=value && !Visible;
            if(opening) Cloak(true);
            base.SetVisibleCore(value);
            // Queue behind WinForms' Shown callbacks, including modal dialogs and
            // subsequent shows. No fixed delay or nested message loop is needed.
            if(opening && IsHandleCreated && Visible) BeginInvoke(new MethodInvoker(Reveal));
        }
        void Reveal() {
            if(IsDisposed || !IsHandleCreated || !Visible || !cloaked) return;
            try {
                PerformLayout();
                // Paint the frame and all child HWNDs into the hidden DWM surface.
                // INVALIDATE | ERASE | ALLCHILDREN | UPDATENOW | FRAME
                RedrawWindow(Handle,IntPtr.Zero,IntPtr.Zero,0x0585);
            } finally { if(!IsDisposed && IsHandleCreated) Cloak(false); }
        }
        // Native lists manage their own paint buffers. Compositing the entire
        // HWND tree delays presenting those buffers during scrolling/selection.
        // The initial reveal above already prevents partially painted openings.
    }
    // Shared dialog styling stays here so the standalone brightness panel can use it too.
    public class DialogTextInput : UserControl {
        public readonly TextBox Editor=new TextBox();
        public DialogTextInput() {
            DoubleBuffered=true; TabStop=false; Size=new Size(200,36);
            Editor.BorderStyle=BorderStyle.None;
            Controls.Add(Editor);
            Editor.Enter+=delegate { Invalidate(); }; Editor.Leave+=delegate { Invalidate(); };
            Editor.TextChanged+=delegate { OnTextChanged(EventArgs.Empty); };
            EnabledChanged+=delegate { ApplyTheme(); Invalidate(); };
        }
        public override string Text { get { return Editor==null?"":Editor.Text; } set { if(Editor!=null) Editor.Text=value; } }
        protected virtual int ReservedWidth { get { return 0; } }
        protected override void OnLayout(LayoutEventArgs e) {
            base.OnLayout(e);
            if(Editor==null) return;
            int pad=Math.Max(8,(int)(10*Font.Size/10));
            Editor.SetBounds(pad,Math.Max(2,(Height-Editor.PreferredHeight)/2),Math.Max(10,Width-2*pad-ReservedWidth),Editor.PreferredHeight);
            Editor.AccessibleName=AccessibleName;
        }
        protected override void OnPaint(PaintEventArgs e) {
            base.OnPaint(e);
            if(SystemInformation.HighContrast) { ControlPaint.DrawBorder(e.Graphics,ClientRectangle,SystemColors.WindowText,ButtonBorderStyle.Solid); return; }
            e.Graphics.SmoothingMode=System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
            using(var path=DialogTheme.Round(new RectangleF(.5f,.5f,Width-1,Height-1),6))
            using(var fill=new SolidBrush(DialogTheme.Surface))
            using(var pen=new Pen(ContainsFocus?DialogTheme.Accent:DialogTheme.Border)) { e.Graphics.FillPath(fill,path); e.Graphics.DrawPath(pen,path); }
        }
        public void ApplyTheme() {
            if(SystemInformation.HighContrast) return;
            BackColor=DialogTheme.Background; Editor.BackColor=DialogTheme.Surface; Editor.ForeColor=Enabled?DialogTheme.Text:DialogTheme.Muted; Editor.BorderStyle=BorderStyle.None;
        }
    }
    public sealed class DialogNumberInput : DialogTextInput {
        readonly DialogButton decrease=new DialogButton(),increase=new DialogButton();
        int current,minimum,maximum=300;
        public int Minimum { get { return minimum; } set { minimum=value; Value=current; } }
        public int Maximum { get { return maximum; } set { maximum=value; Value=current; } }
        public int Value { get { Commit(); return current; } set { current=Math.Max(minimum,Math.Min(maximum,value)); Editor.Text=current.ToString(); } }
        protected override int ReservedWidth { get { return (int)(64*Font.Size/10); } }
        public DialogNumberInput() {
            Editor.Text="0"; Editor.TextAlign=HorizontalAlignment.Center;
            decrease.Text="\u2212"; increase.Text="+"; decrease.StepGlyph=-1; increase.StepGlyph=1;
            decrease.AccessibleName="Decrease delay"; increase.AccessibleName="Increase delay";
            Controls.AddRange(new Control[]{decrease,increase});
            decrease.Click+=delegate { Step(-1); }; increase.Click+=delegate { Step(1); };
            Editor.Leave+=delegate { Commit(); };
            Editor.KeyDown+=delegate(object sender,KeyEventArgs e) {
                if(e.KeyCode==Keys.Up || e.KeyCode==Keys.Down) { Step(e.KeyCode==Keys.Up?1:-1); e.SuppressKeyPress=true; }
            };
        }
        void Commit() { int parsed; Value=Int32.TryParse(Editor.Text,out parsed)?parsed:current; }
        public void Step(int amount) { Value=Value+amount; Editor.Focus(); Editor.SelectAll(); }
        protected override void OnLayout(LayoutEventArgs e) {
            base.OnLayout(e); if(decrease==null || increase==null) return;
            int side=ReservedWidth/2;
            decrease.SetBounds(Width-2*side-4,4,side,Height-8); increase.SetBounds(Width-side-4,4,side,Height-8);
        }
    }
    public static class DialogTheme {
        internal const string SavingCaption="Saving\u2026", SavingText="\u2193 "+SavingCaption;
        internal const string SavedText="\u2713 Saved";
        internal const int SavedMilliseconds=2000;
        public static readonly Color Background=Color.FromArgb(24,26,29), Surface=Color.FromArgb(34,37,41),
            Text=Color.FromArgb(237,240,243), Muted=Color.FromArgb(160,168,178), Accent=Color.FromArgb(137,214,190),
            Border=Color.FromArgb(59,64,71), Selection=Color.FromArgb(49,76,70);
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr window,int attribute,ref int value,int size);
        [DllImport("uxtheme.dll",CharSet=CharSet.Unicode)] static extern int SetWindowTheme(IntPtr window,string application,string classes);
        public static GraphicsPath Round(RectangleF rect,float radius) {
            var path=new GraphicsPath(); float d=radius*2;
            path.AddArc(rect.X,rect.Y,d,d,180,90); path.AddArc(rect.Right-d,rect.Y,d,d,270,90);
            path.AddArc(rect.Right-d,rect.Bottom-d,d,d,0,90); path.AddArc(rect.X,rect.Bottom-d,d,d,90,90); path.CloseFigure(); return path;
        }
        public static Label Heading(string text,int x,int y,int width) {
            return new Label {Text=text,Bounds=new Rectangle(x,y,width,38),Font=new Font("Segoe UI Semibold",21),AutoEllipsis=true};
        }
        public static Label Caption(string text,int x,int y,int width,int height) {
            return new Label {Text=text,Bounds=new Rectangle(x,y,width,height),Tag="muted"};
        }
        public static void AddSettingsHeader(Control page,string title,string description) {
            var caption=Caption(description,24,65,page.ClientSize.Width-48,28);
            caption.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right;
            page.Controls.Add(Heading(title,24,20,400));
            page.Controls.Add(caption);
        }
        internal static Pen MarkPen(Color color,float scale) {
            return new Pen(color,2*scale) {StartCap=LineCap.Round,EndCap=LineCap.Round,LineJoin=LineJoin.Round};
        }
        public static void DrawCheck(Graphics g,RectangleF bounds,CheckState state,bool enabled,bool highlighted,bool focused) {
            var saved=g.Save(); g.SmoothingMode=SmoothingMode.AntiAlias;
            float scale=bounds.Width/18f;
            if(focused) using(var path=Round(RectangleF.Inflate(bounds,3*scale,3*scale),6*scale)) using(var pen=new Pen(Accent,Math.Max(1,scale))) g.DrawPath(pen,path);
            bool marked=state!=CheckState.Unchecked;
            Color fill=marked?(enabled?Accent:Border):Surface;
            Color edge=enabled && highlighted?Accent:enabled?Muted:Border;
            using(var path=Round(bounds,4*scale)) using(var brush=new SolidBrush(fill)) using(var pen=new Pen(marked?fill:edge,Math.Max(1,scale))) {
                g.FillPath(brush,path); g.DrawPath(pen,path);
            }
            if(marked) using(var pen=MarkPen(enabled?Background:Muted,scale)) {
                float x=bounds.Left,y=bounds.Top;
                if(state==CheckState.Indeterminate) g.DrawLine(pen,x+5*scale,y+9*scale,x+13*scale,y+9*scale);
                else g.DrawLines(pen,new PointF[]{new PointF(x+4*scale,y+9*scale),new PointF(x+7.5f*scale,y+12.5f*scale),new PointF(x+14*scale,y+5.5f*scale)});
            }
            g.Restore(saved);
        }
        internal static void DrawListCell(ListView list,Graphics graphics,ListViewItem item,int column,Rectangle cell,bool selected,int checkSlot) {
            if(cell.Width<=0) return;
            var bounds=cell; bounds.Inflate(-12,0);
            if(checkSlot>0) {
                int side=Math.Max(8,Math.Min(checkSlot-2,(int)Math.Round(16*graphics.DpiX/96f)));
                var clip=cell.Width<checkSlot ? graphics.Save() : null;
                if(clip!=null) graphics.SetClip(cell,CombineMode.Intersect);
                DrawCheck(graphics,new RectangleF(cell.Left+(checkSlot-side)/2,cell.Top+(cell.Height-side)/2,side,side),
                    item.Checked?CheckState.Checked:CheckState.Unchecked,list.Enabled,false,false);
                if(clip!=null) graphics.Restore(clip);
                bounds.X+=checkSlot; bounds.Width-=checkSlot;
            }
            string text=item.SubItems[column].Text;
            if(bounds.Width>0 && text.Length>0)
                TextRenderer.DrawText(graphics,text,list.Font,bounds,column==0?Text:Muted,TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis|TextFormatFlags.NoPrefix);
            if(selected && list.Focused && column==0) ControlPaint.DrawFocusRectangle(graphics,cell,Text,Selection);
        }
        public static void Apply(Control control) {
            if(SystemInformation.HighContrast) return;
            control.BackColor=Background; control.ForeColor=Text;
            if(control is ListView || control is ListBox || control is ScrollBar || (control is ScrollableControl && ((ScrollableControl)control).AutoScroll)) {
                control.HandleCreated+=delegate { SetWindowTheme(control.Handle,"DarkMode_Explorer",null); };
                if(control.IsHandleCreated) SetWindowTheme(control.Handle,"DarkMode_Explorer",null);
            }
            if((string)(control.Tag as string)=="muted") control.ForeColor=Muted;
            var form=control as Form;
            if(form!=null) form.HandleCreated+=delegate {
                try { int dark=1,round=2; DwmSetWindowAttribute(form.Handle,20,ref dark,4); DwmSetWindowAttribute(form.Handle,33,ref round,4); }
                catch(DllNotFoundException) { } catch(EntryPointNotFoundException) { }
            };
            var button=control as Button;
            if(button!=null) { button.FlatStyle=FlatStyle.Flat; button.FlatAppearance.BorderSize=0; button.BackColor=Surface; button.Cursor=Cursors.Hand; }
            if(control is TextBox || control is ComboBox || control is NumericUpDown || control is CheckedListBox) control.BackColor=Surface;
            var text=control as TextBox; if(text!=null) text.BorderStyle=BorderStyle.FixedSingle;
            var combo=control as ComboBox; if(combo!=null && !(combo is DialogComboBox)) {
                combo.FlatStyle=FlatStyle.Flat; combo.DrawMode=DrawMode.OwnerDrawFixed; combo.ItemHeight=24;
                combo.DrawItem+=delegate(object sender,DrawItemEventArgs e) {
                    using(var brush=new SolidBrush((e.State&DrawItemState.Selected)!=0?Selection:Surface)) e.Graphics.FillRectangle(brush,e.Bounds);
                    string label=e.Index>=0?combo.GetItemText(combo.Items[e.Index]):combo.Text;
                    var bounds=e.Bounds; bounds.Inflate(-6,0);
                    TextRenderer.DrawText(e.Graphics,label,combo.Font,bounds,combo.Enabled?Text:Muted,TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);
                    if((e.State&DrawItemState.Focus)!=0) e.DrawFocusRectangle();
                };
            }
            var checks=control as CheckedListBox; if(checks!=null) { checks.BorderStyle=BorderStyle.None; checks.IntegralHeight=false; }
            var list=control as ListView;
            if(list!=null) {
                list.BorderStyle=BorderStyle.None; list.BackColor=Surface; list.OwnerDraw=true;
                // An image slot gives native rows comfortable, DPI-scaled vertical spacing.
                var spacing=new ImageList {ImageSize=new Size(1,36),ColorDepth=ColorDepth.Depth32Bit}; list.SmallImageList=spacing;
                list.Disposed+=delegate { spacing.Dispose(); };
                list.DrawColumnHeader+=delegate(object sender,DrawListViewColumnHeaderEventArgs e) {
                    using(var brush=new SolidBrush(Surface)) e.Graphics.FillRectangle(brush,e.Bounds);
                    var bounds=e.Bounds; bounds.Inflate(-12,0);
                    TextRenderer.DrawText(e.Graphics,e.Header.Text,list.Font,bounds,Muted,TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis|TextFormatFlags.NoPrefix);
                };
                list.DrawItem+=delegate(object sender,DrawListViewItemEventArgs e) { if(list.View!=View.Details) e.DrawDefault=true; };
                list.DrawSubItem+=delegate(object sender,DrawListViewSubItemEventArgs e) {
                    bool selected=e.Item.Selected;
                    using(var brush=new SolidBrush(selected?Selection:Surface)) e.Graphics.FillRectangle(brush,e.Bounds);
                    int slot=e.ColumnIndex==0 && list.CheckBoxes ? list.GetItemRect(e.ItemIndex,ItemBoundsPortion.Label).Left-e.Bounds.Left : 0;
                    DrawListCell(list,e.Graphics,e.Item,e.ColumnIndex,e.Bounds,selected,slot);
                };
            }
            var grid=control as DataGridView;
            if(grid!=null) {
                grid.BackgroundColor=Surface; grid.BorderStyle=BorderStyle.None; grid.CellBorderStyle=DataGridViewCellBorderStyle.SingleHorizontal;
                grid.GridColor=Border; grid.EnableHeadersVisualStyles=false; grid.ColumnHeadersBorderStyle=DataGridViewHeaderBorderStyle.None;
                grid.ColumnHeadersHeight=38; grid.ColumnHeadersHeightSizeMode=DataGridViewColumnHeadersHeightSizeMode.DisableResizing;
                grid.RowTemplate.Height=38; grid.DefaultCellStyle.BackColor=Surface; grid.DefaultCellStyle.ForeColor=Text;
                grid.DefaultCellStyle.SelectionBackColor=Selection; grid.DefaultCellStyle.SelectionForeColor=Text;
                grid.DefaultCellStyle.Padding=new Padding(8,4,8,4);
                grid.ColumnHeadersDefaultCellStyle.BackColor=Surface; grid.ColumnHeadersDefaultCellStyle.ForeColor=Muted;
                grid.ColumnHeadersDefaultCellStyle.SelectionBackColor=Surface;
                Action sizeRows=delegate {
                    int height=(int)Math.Round(38*grid.Font.Size/10f);
                    grid.RowTemplate.Height=height; grid.ColumnHeadersHeight=height;
                    foreach(DataGridViewRow row in grid.Rows) row.Height=height;
                };
                grid.FontChanged+=delegate { sizeRows(); }; sizeRows();
            }
            foreach(Control child in control.Controls) Apply(child);
            var paddedInput=control as DialogTextInput;
            if(paddedInput!=null) paddedInput.ApplyTheme();
        }
    }
    internal class SaveStatusLabel : Label {
        readonly System.Windows.Forms.Timer timer=new System.Windows.Forms.Timer();
        const int MinimumSavingMilliseconds=600;
        bool saving;
        string idleText="", confirmation;

        internal SaveStatusLabel() {
            timer.Tick+=delegate {
                timer.Stop();
                if(!saving) ClearFeedback();
                else if(confirmation!=null) ShowConfirmation();
            };
        }
        internal void SetIdleText(string message) {
            idleText=message;
            if(!saving && !timer.Enabled) Text=message;
        }
        internal void BeginSaving() {
            confirmation=null;
            if(saving) return;
            saving=true;
            Text=DialogTheme.SavingText;
            timer.Interval=MinimumSavingMilliseconds;
            timer.Start();
        }
        internal void Confirm(string message) {
            BeginSaving();
            confirmation=message;
            if(!timer.Enabled) ShowConfirmation();
        }
        void ShowConfirmation() {
            saving=false;
            Text=confirmation;
            timer.Interval=DialogTheme.SavedMilliseconds;
            timer.Start();
        }
        internal void ClearUnconfirmed() {
            if(saving && confirmation==null) ClearFeedback();
        }
        internal void ClearFeedback() {
            timer.Stop();
            saving=false; confirmation=null;
            Text=idleText;
        }
        protected override void OnPaint(PaintEventArgs e) {
            if(!saving) { base.OnPaint(e); return; }
            float scale=Font.Size/10f;
            bool centered=TextAlign==ContentAlignment.MiddleLeft;
            float centerY=(centered?ClientSize.Height:Font.Height)/2f;
            float x=7*scale, tip=centerY+5*scale;
            var color=Enabled?ForeColor:SystemColors.GrayText;
            e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
            using(var pen=DialogTheme.MarkPen(color,scale)) {
                e.Graphics.DrawLine(pen,x,centerY-5*scale,x,tip);
                e.Graphics.DrawLines(pen,new[]{new PointF(x-4*scale,tip-4*scale),new PointF(x,tip),new PointF(x+4*scale,tip-4*scale)});
            }
            int left=(int)Math.Ceiling(15*scale);
            var caption=new Rectangle(left,0,Math.Max(0,Width-left),Height);
            TextRenderer.DrawText(e.Graphics,DialogTheme.SavingCaption,Font,caption,color,TextFormatFlags.SingleLine|
                TextFormatFlags.NoPadding|TextFormatFlags.NoPrefix|(centered?TextFormatFlags.VerticalCenter:TextFormatFlags.Top));
        }
        protected override void Dispose(bool disposing) {
            if(disposing) timer.Dispose();
            base.Dispose(disposing);
        }
    }
    public class DialogListView : ListView {
        public DialogListView() { DoubleBuffered=true; }
        internal virtual void FitColumns() {
            if(Columns.Count==1 && Columns[0].Width!=ClientSize.Width) Columns[0].Width=ClientSize.Width;
        }
        protected override void OnSizeChanged(EventArgs e) { base.OnSizeChanged(e); FitColumns(); }
        protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); FitColumns(); }
        protected override void WndProc(ref Message m) {
            if(m.Msg==0x003d /* WM_GETOBJECT */) {
                // SysListView32 already exposes native MSAA/UI Automation. The
                // Framework AccessibleObject bridge can block in COM marshaling
                // when an external accessibility client inspects a hosted list.
                // Keep the native provider, including virtual row text/selection.
                DefWndProc(ref m); return;
            }
            base.WndProc(ref m);
        }
    }
    public sealed class DialogMessageForm : DialogForm {
        public readonly Label MessageText=new Label();
        public DialogMessageForm(string message,MessageBoxButtons buttons) {
            Text="HDR Control"; Font=new Font("Segoe UI",10);
            AutoScaleDimensions=new SizeF(96,96); AutoScaleMode=AutoScaleMode.Dpi;
            StartPosition=FormStartPosition.CenterScreen; MinimizeBox=false; MaximizeBox=false;
            FormBorderStyle=FormBorderStyle.FixedDialog;
            int textHeight=TextRenderer.MeasureText(message,Font,new Size(512,0),TextFormatFlags.WordBreak|TextFormatFlags.NoPrefix).Height;
            ClientSize=new Size(560,Math.Max(220,Math.Min(600,textHeight+160)));
            var title=DialogTheme.Heading("HDR Control",24,20,512);
            var body=new Panel {Bounds=new Rectangle(24,76,512,ClientSize.Height-160),AutoScroll=true,Anchor=AnchorStyles.Top|AnchorStyles.Bottom|AnchorStyles.Left|AnchorStyles.Right};
            MessageText.Text=message; MessageText.UseMnemonic=false; MessageText.AutoSize=true; MessageText.MaximumSize=new Size(490,0);
            body.Controls.Add(MessageText);
            var footer=new FlowLayoutPanel {Dock=DockStyle.Bottom,Height=72,Padding=new Padding(16),FlowDirection=FlowDirection.RightToLeft,WrapContents=false};
            DialogResult[] results;
            switch(buttons) {
                case MessageBoxButtons.OK: results=new[]{DialogResult.OK}; break;
                case MessageBoxButtons.OKCancel: results=new[]{DialogResult.OK,DialogResult.Cancel}; break;
                case MessageBoxButtons.YesNo: results=new[]{DialogResult.Yes,DialogResult.No}; break;
                case MessageBoxButtons.YesNoCancel: results=new[]{DialogResult.Yes,DialogResult.No,DialogResult.Cancel}; break;
                case MessageBoxButtons.RetryCancel: results=new[]{DialogResult.Retry,DialogResult.Cancel}; break;
                default: throw new ArgumentOutOfRangeException("buttons");
            }
            for(int i=results.Length-1;i>=0;i--) {
                var button=new DialogButton {Text=results[i].ToString(),DialogResult=results[i],Size=new Size(104,36),Margin=new Padding(6,0,0,0),Primary=i==0,TabIndex=i};
                footer.Controls.Add(button);
                if(i==0) AcceptButton=button;
                if(i==results.Length-1) CancelButton=button;
            }
            Controls.AddRange(new Control[]{title,body,footer}); DialogTheme.Apply(this);
            Load+=delegate { var area=Screen.FromControl(this).WorkingArea; if(Height>area.Height-32) Height=Math.Max(180,area.Height-32); };
        }
    }
    public sealed class DialogCheckBox : CheckBox {
        bool hovering;
        public DialogCheckBox() {
            SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw,true);
            Cursor=Cursors.Hand;
        }
        protected override void OnMouseEnter(EventArgs e) { hovering=true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hovering=false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnPaint(PaintEventArgs e) {
            if(SystemInformation.HighContrast) { base.OnPaint(e); return; }
            using(var brush=new SolidBrush(BackColor)) e.Graphics.FillRectangle(brush,ClientRectangle);
            float scale=Font.Size/10f,side=18*scale;
            DialogTheme.DrawCheck(e.Graphics,new RectangleF(4*scale,(Height-side)/2,side,side),CheckState,Enabled,hovering,Focused && ShowFocusCues);
            var label=new Rectangle((int)(32*scale),0,Math.Max(0,Width-(int)(32*scale)),Height);
            TextRenderer.DrawText(e.Graphics,Text,Font,label,Enabled?ForeColor:DialogTheme.Muted,
                TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis|(ShowKeyboardCues?TextFormatFlags.Default:TextFormatFlags.HidePrefix));
        }
    }
    public sealed class DialogCheckedListBox : CheckedListBox {
        int hoverIndex=-1;
        public DialogCheckedListBox() { CheckOnClick=true; Cursor=Cursors.Hand; }
        public override int ItemHeight {
            get { return SystemInformation.HighContrast?base.ItemHeight:Math.Max(Font.Height+12,(int)Math.Round(34*Font.Size/10f)); }
            set { base.ItemHeight=value; }
        }
        protected override void OnMouseMove(MouseEventArgs e) {
            int index=IndexFromPoint(e.Location); if(index!=hoverIndex) { hoverIndex=index; Invalidate(); }
            base.OnMouseMove(e);
        }
        protected override void OnMouseLeave(EventArgs e) { hoverIndex=-1; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnDrawItem(DrawItemEventArgs e) {
            if(SystemInformation.HighContrast) { base.OnDrawItem(e); return; }
            bool selected=(e.State&DrawItemState.Selected)!=0,focused=(e.State&DrawItemState.Focus)!=0 && Focused;
            using(var brush=new SolidBrush(Enabled && (selected || e.Index==hoverIndex)?DialogTheme.Selection:BackColor)) e.Graphics.FillRectangle(brush,e.Bounds);
            if(e.Index<0 || e.Index>=Items.Count) return;
            float scale=Font.Size/10f,side=18*scale;
            DialogTheme.DrawCheck(e.Graphics,new RectangleF(e.Bounds.Left+10*scale,e.Bounds.Top+(e.Bounds.Height-side)/2,side,side),GetItemCheckState(e.Index),Enabled,e.Index==hoverIndex,focused && ShowFocusCues);
            var label=e.Bounds; label.X+=(int)(40*scale); label.Width-=(int)(48*scale);
            TextRenderer.DrawText(e.Graphics,GetItemText(Items[e.Index]),Font,label,Enabled?ForeColor:DialogTheme.Muted,
                TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis|TextFormatFlags.NoPrefix);
        }
    }
    public sealed class DialogCheckBoxCell : DataGridViewCheckBoxCell {
        protected override Rectangle GetContentBounds(Graphics graphics,DataGridViewCellStyle cellStyle,int rowIndex) {
            if(SystemInformation.HighContrast || DataGridView==null || rowIndex<0) return base.GetContentBounds(graphics,cellStyle,rowIndex);
            int width=DataGridView.Columns[ColumnIndex].Width,height=DataGridView.Rows[rowIndex].Height;
            int side=Math.Max(8,Math.Min((int)Math.Round(18*cellStyle.Font.Size/10f),Math.Min(width,height)-10));
            return new Rectangle((width-side)/2,(height-side)/2,side,side);
        }
        protected override void Paint(Graphics graphics,Rectangle clipBounds,Rectangle cellBounds,int rowIndex,DataGridViewElementStates cellState,
            object value,object formattedValue,string errorText,DataGridViewCellStyle cellStyle,DataGridViewAdvancedBorderStyle borderStyle,DataGridViewPaintParts paintParts) {
            if(SystemInformation.HighContrast) { base.Paint(graphics,clipBounds,cellBounds,rowIndex,cellState,value,formattedValue,errorText,cellStyle,borderStyle,paintParts); return; }
            base.Paint(graphics,clipBounds,cellBounds,rowIndex,cellState,value,formattedValue,errorText,cellStyle,borderStyle,paintParts & ~DataGridViewPaintParts.ContentForeground);
            if((paintParts&DataGridViewPaintParts.ContentForeground)==0) return;
            CheckState state=formattedValue is CheckState?(CheckState)formattedValue:formattedValue is bool && (bool)formattedValue?CheckState.Checked:CheckState.Unchecked;
            var bounds=GetContentBounds(graphics,cellStyle,rowIndex); bounds.Offset(cellBounds.Location);
            var saved=graphics.Save(); graphics.SetClip(Rectangle.Intersect(clipBounds,cellBounds));
            DialogTheme.DrawCheck(graphics,bounds,state,DataGridView.Enabled && !ReadOnly,false,false); graphics.Restore(saved);
        }
    }
    public sealed class DialogSlider : TrackBar {
        [StructLayout(LayoutKind.Sequential)] struct NativeRect { public int Left,Top,Right,Bottom; }
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr window,int message,IntPtr wparam,ref NativeRect rect);
        [DllImport("user32.dll",EntryPoint="SendMessageW")] static extern IntPtr SendValue(IntPtr window,int message,IntPtr wparam,IntPtr lparam);
        bool hovering;
        public DialogSlider() {
            AutoSize=false; TickStyle=TickStyle.None; Cursor=Cursors.Hand;
            UpdatePaintStyle();
        }
        void UpdatePaintStyle() {
            // Present the background, track and thumb together. High contrast uses the native trackbar.
            SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer|ControlStyles.ResizeRedraw,
                !SystemInformation.HighContrast);
        }
        protected override void OnSystemColorsChanged(EventArgs e) { UpdatePaintStyle(); base.OnSystemColorsChanged(e); Invalidate(); }
        protected override CreateParams CreateParams { get { var cp=base.CreateParams; cp.Style|=0x40; return cp; } }
        void SizeThumb() { if(IsHandleCreated) SendValue(Handle,0x41b,(IntPtr)(int)Math.Round(30*Font.Size/10f),IntPtr.Zero); }
        protected override void OnHandleCreated(EventArgs e) { base.OnHandleCreated(e); SizeThumb(); }
        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); SizeThumb(); Invalidate(); }
        protected override void OnMouseEnter(EventArgs e) { hovering=true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hovering=false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnValueChanged(EventArgs e) { base.OnValueChanged(e); Invalidate(); }
        protected override void OnPaint(PaintEventArgs e) {
            var g=e.Graphics;
            var thumb=new NativeRect(); var channel=new NativeRect();
            SendMessage(Handle,0x419,IntPtr.Zero,ref thumb); SendMessage(Handle,0x41a,IntPtr.Zero,ref channel);
            float scale=Font.Size/10f,x=(thumb.Left+thumb.Right)/2f,y=(thumb.Top+thumb.Bottom)/2f;
            g.SmoothingMode=SmoothingMode.AntiAlias;
            // Use Windows' actual thumb and channel geometry so the drawing stays
            // aligned with native dragging, hit testing, arrow keys, and page steps.
            using(var track=new Pen(DialogTheme.Border,5*scale)) {
                track.StartCap=track.EndCap=LineCap.Round; g.DrawLine(track,channel.Left,y,channel.Right,y);
            }
            if(x>channel.Left) using(var fill=new Pen(Enabled?DialogTheme.Accent:DialogTheme.Muted,5*scale)) {
                fill.StartCap=fill.EndCap=LineCap.Round; g.DrawLine(fill,channel.Left,y,x,y);
            }
            float diameter=Math.Min(thumb.Right-thumb.Left,thumb.Bottom-thumb.Top),radius=diameter/2f;
            if(Enabled && (hovering || Focused)) using(var brush=new SolidBrush(DialogTheme.Selection)) g.FillEllipse(brush,x-radius-4*scale,y-radius-4*scale,diameter+8*scale,diameter+8*scale);
            using(var brush=new SolidBrush(Enabled?DialogTheme.Accent:DialogTheme.Muted)) g.FillEllipse(brush,x-radius,y-radius,diameter,diameter);
            using(var brush=new SolidBrush(DialogTheme.Surface)) g.FillEllipse(brush,x-3*scale,y-3*scale,6*scale,6*scale);
            if(Focused && ShowFocusCues) using(var pen=new Pen(DialogTheme.Accent,Math.Max(1,scale))) g.DrawEllipse(pen,x-radius-4*scale,y-radius-4*scale,diameter+8*scale,diameter+8*scale);
        }
    }
    // Keep the native combo box's keyboard, selection, and accessibility behavior,
    // while painting the whole closed field (including the native arrow area).
    public sealed class DialogComboBox : ComboBox {
        [StructLayout(LayoutKind.Sequential)] struct NativeRect { public int Left,Top,Right,Bottom; }
        [StructLayout(LayoutKind.Sequential)] struct ComboInfo {
            public int Size; public NativeRect Item,Button; public int State;
            public IntPtr Combo,Edit,List;
        }
        [DllImport("user32.dll")] static extern bool GetComboBoxInfo(IntPtr handle,ref ComboInfo info);
        [DllImport("user32.dll")] static extern IntPtr GetWindowDC(IntPtr handle);
        [DllImport("user32.dll")] static extern int ReleaseDC(IntPtr handle,IntPtr dc);
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr handle,out NativeRect rect);
        [DllImport("user32.dll")] static extern bool InvalidateRect(IntPtr window,IntPtr rect,bool erase);
        sealed class PopupFrame : NativeWindow {
            protected override void WndProc(ref Message m) {
                base.WndProc(ref m);
                if(SystemInformation.HighContrast || (m.Msg!=0x85 && m.Msg!=0xf && m.Msg!=0x14)) return;
                NativeRect rect;
                if(!GetWindowRect(Handle,out rect)) return;
                IntPtr dc=GetWindowDC(Handle); if(dc==IntPtr.Zero) return;
                try { using(var g=Graphics.FromHdc(dc)) using(var pen=new Pen(DialogTheme.Border,2))
                    g.DrawRectangle(pen,1,1,rect.Right-rect.Left-2,rect.Bottom-rect.Top-2);
                } finally { ReleaseDC(Handle,dc); }
            }
        }
        readonly PopupFrame popup=new PopupFrame();
        bool hovering;
        int? popupSelection;
        // The native list temporarily reports the hovered row as SelectedIndex
        // without raising a selection change.
        internal int ValueIndex { get { return popupSelection ?? SelectedIndex; } }
        public DialogComboBox() {
            SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,!SystemInformation.HighContrast);
            DropDownStyle=ComboBoxStyle.DropDownList; DrawMode=DrawMode.OwnerDrawFixed;
            FlatStyle=FlatStyle.Flat; MaxDropDownItems=10; IntegralHeight=true;
            BackColor=DialogTheme.Surface; ForeColor=DialogTheme.Text; Cursor=Cursors.Hand;
            UpdateMetrics();
        }
        int Px(float value) { return (int)Math.Round(value*Font.Size/10f); }
        void UpdateMetrics() { ItemHeight=Math.Max(Font.Height+8,Px(30)); }
        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); UpdateMetrics(); }
        protected override void OnMouseEnter(EventArgs e) { hovering=true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hovering=false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnGotFocus(EventArgs e) { base.OnGotFocus(e); Invalidate(); }
        protected override void OnLostFocus(EventArgs e) { base.OnLostFocus(e); Invalidate(); }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnSelectedIndexChanged(EventArgs e) {
            if(popupSelection.HasValue && popupSelection.Value!=SelectedIndex) {
                popupSelection=SelectedIndex;
                if(popup.Handle!=IntPtr.Zero) InvalidateRect(popup.Handle,IntPtr.Zero,false);
            }
            base.OnSelectedIndexChanged(e); Invalidate();
        }
        protected override void OnDropDown(EventArgs e) {
            popupSelection=SelectedIndex;
            var info=new ComboInfo {Size=Marshal.SizeOf(typeof(ComboInfo))};
            if(GetComboBoxInfo(Handle,ref info) && info.List!=IntPtr.Zero && popup.Handle!=info.List) {
                if(popup.Handle!=IntPtr.Zero) popup.ReleaseHandle(); popup.AssignHandle(info.List);
            }
            base.OnDropDown(e); Invalidate();
        }
        protected override void OnDropDownClosed(EventArgs e) { popupSelection=null; base.OnDropDownClosed(e); Invalidate(); }
        protected override void OnHandleDestroyed(EventArgs e) {
            popupSelection=null;
            if(popup!=null && popup.Handle!=IntPtr.Zero) popup.ReleaseHandle();
            base.OnHandleDestroyed(e);
        }
        protected override void OnDrawItem(DrawItemEventArgs e) {
            if(SystemInformation.HighContrast) {
                e.DrawBackground();
                TextRenderer.DrawText(e.Graphics,e.Index<0?Text:GetItemText(Items[e.Index]),Font,e.Bounds,SystemColors.ControlText,TextFormatFlags.VerticalCenter);
                e.DrawFocusRectangle(); return;
            }
            e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
            using(var brush=new SolidBrush(DialogTheme.Surface)) e.Graphics.FillRectangle(brush,e.Bounds);
            bool highlighted=(e.State&DrawItemState.Selected)!=0;
            if(highlighted) {
                var row=Rectangle.Inflate(e.Bounds,-Px(3),-Px(2));
                using(var path=DialogTheme.Round(row,Px(5))) using(var brush=new SolidBrush(DialogTheme.Selection)) e.Graphics.FillPath(brush,path);
            }
            var bounds=e.Bounds; bounds.X+=Px(12); bounds.Width-=Px(40);
            TextRenderer.DrawText(e.Graphics,e.Index<0?Text:GetItemText(Items[e.Index]),Font,bounds,Enabled?DialogTheme.Text:DialogTheme.Muted,
                TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis|TextFormatFlags.NoPrefix);
            if(e.Index>=0 && e.Index==ValueIndex) {
                float x=e.Bounds.Right-Px(20),y=e.Bounds.Top+e.Bounds.Height/2f;
                using(var pen=new Pen(DialogTheme.Accent,Math.Max(1.5f,Px(1.5f)))) {
                    pen.StartCap=pen.EndCap=LineCap.Round; pen.LineJoin=LineJoin.Round;
                    e.Graphics.DrawLines(pen,new PointF[]{new PointF(x-Px(4),y),new PointF(x-Px(1),y+Px(3)),new PointF(x+Px(5),y-Px(3))});
                }
            }
        }
        void PaintField(Graphics g) {
            if(Width<4 || Height<4) return;
            using(var background=new SolidBrush(Parent==null?DialogTheme.Background:Parent.BackColor)) g.FillRectangle(background,ClientRectangle);
            g.SmoothingMode=SmoothingMode.AntiAlias;
            Color edge=Enabled && (Focused || DroppedDown)?DialogTheme.Accent:hovering && Enabled?DialogTheme.Muted:DialogTheme.Border;
            using(var path=DialogTheme.Round(new RectangleF(1,1,Width-3,Height-3),Px(7)))
            using(var fill=new SolidBrush(DialogTheme.Surface)) using(var pen=new Pen(edge)) { g.FillPath(fill,path); g.DrawPath(pen,path); }
            var bounds=new Rectangle(Px(12),0,Math.Max(0,Width-Px(48)),Height);
            int index=ValueIndex;
            string label=index>=0 && index<Items.Count ? GetItemText(Items[index]) : "";
            TextRenderer.DrawText(g,label,Font,bounds,Enabled?DialogTheme.Text:DialogTheme.Muted,
                TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis|TextFormatFlags.NoPrefix);
            float x=Width-Px(20),y=Height/2f; float direction=DroppedDown?-1:1;
            using(var pen=new Pen(Enabled?DialogTheme.Muted:DialogTheme.Border,Math.Max(1.5f,Px(1.5f)))) {
                pen.StartCap=pen.EndCap=LineCap.Round; pen.LineJoin=LineJoin.Round;
                g.DrawLines(pen,new PointF[]{new PointF(x-Px(4),y-direction*Px(2)),new PointF(x,y+direction*Px(2)),new PointF(x+Px(4),y-direction*Px(2))});
            }
        }
        protected override void OnPaint(PaintEventArgs e) {
            if(SystemInformation.HighContrast) base.OnPaint(e); else PaintField(e.Graphics);
        }
        protected override void WndProc(ref Message m) {
            if(!SystemInformation.HighContrast && (m.Msg==0x317 || m.Msg==0x318) && m.WParam!=IntPtr.Zero) {
                using(var g=Graphics.FromHdc(m.WParam)) PaintField(g);
                return;
            }
            base.WndProc(ref m);
        }
    }
    public sealed class DialogButton : Button {
        public bool Primary;
        public int StepGlyph;
        bool hovering,pressed;
        public DialogButton() { SetStyle(ControlStyles.UserPaint|ControlStyles.AllPaintingInWmPaint|ControlStyles.OptimizedDoubleBuffer,true); }
        protected override void OnMouseEnter(EventArgs e) { hovering=true; Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { hovering=false; pressed=false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { pressed=true; Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e) { pressed=false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnPaint(PaintEventArgs e) {
            if(SystemInformation.HighContrast) { base.OnPaint(e); return; }
            e.Graphics.Clear(Parent==null?DialogTheme.Background:Parent.BackColor); e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
            Color fill=Primary?DialogTheme.Accent:DialogTheme.Surface;
            if(!Enabled) fill=DialogTheme.Surface; else if(pressed) fill=ControlPaint.Dark(fill,.12f); else if(hovering) fill=ControlPaint.Light(fill,.12f);
            using(var path=DialogTheme.Round(new RectangleF(1,1,Width-3,Height-3),7*Font.Size/10))
            using(var brush=new SolidBrush(fill)) using(var pen=new Pen(Focused?DialogTheme.Accent:DialogTheme.Border)) {
                e.Graphics.FillPath(brush,path); if(!Primary || Focused) e.Graphics.DrawPath(pen,path);
            }
            Color foreground=!Enabled?DialogTheme.Muted:Primary?DialogTheme.Background:DialogTheme.Text;
            if(StepGlyph!=0) {
                // Center the symbol on the painted button, without font bearings
                // or baseline spacing shifting the visible + / - strokes.
                float x=(Width-1)/2f,y=(Height-1)/2f,arm=4*Font.Size/10f;
                using(var pen=new Pen(foreground,Math.Max(1,Font.Size/10f))) {
                    e.Graphics.DrawLine(pen,x-arm,y,x+arm,y);
                    if(StepGlyph>0) e.Graphics.DrawLine(pen,x,y-arm,x,y+arm);
                }
            } else TextRenderer.DrawText(e.Graphics,Text,Font,ClientRectangle,foreground,
                TextFormatFlags.HorizontalCenter|TextFormatFlags.VerticalCenter|TextFormatFlags.EndEllipsis);
            if(Focused && ShowFocusCues) { var rect=ClientRectangle; rect.Inflate(-5,-5); ControlPaint.DrawFocusRectangle(e.Graphics,rect); }
        }
    }
    public sealed class DialogTabs : Panel {
        public sealed class Pages : System.Collections.ObjectModel.Collection<Panel> {
            readonly DialogTabs owner;
            internal Pages(DialogTabs owner) { this.owner=owner; }
            protected override void InsertItem(int index,Panel page) { base.InsertItem(index,page); owner.AddPage(page); }
            public void AddRange(Panel[] pages) { foreach(var page in pages) Add(page); }
        }
        public readonly Pages TabPages;
        readonly System.Collections.Generic.List<DialogButton> buttons=new System.Collections.Generic.List<DialogButton>();
        int selected=-1;
        public event EventHandler SelectedIndexChanged;
        public DialogTabs() { TabPages=new Pages(this); AccessibleRole=AccessibleRole.PageTabList; }
        public int SelectedIndex {
            get { return selected; }
            set {
                if(value<0 || value>=TabPages.Count || value==selected) return;
                int previous=selected;
                SuspendLayout();
                try {
                    selected=value;
                    if(previous>=0) { TabPages[previous].Visible=false; buttons[previous].Primary=false; buttons[previous].Invalidate(); }
                    TabPages[value].Visible=true; buttons[value].Primary=true; buttons[value].Invalidate();
                } finally { ResumeLayout(true); }
                if(SelectedIndexChanged!=null) SelectedIndexChanged(this,EventArgs.Empty);
            }
        }
        void AddPage(Panel page) {
            int index=buttons.Count;
            var button=new DialogButton {Text=page.Text,AccessibleRole=AccessibleRole.PageTab,TabIndex=index};
            button.Click+=delegate { SelectedIndex=index; };
            page.TextChanged+=delegate { button.Text=page.Text; };
            buttons.Add(button); Controls.Add(button); page.Visible=false; Controls.Add(page);
            if(selected<0) SelectedIndex=0;
            LayoutPages();
        }
        void LayoutPages() {
            if(buttons==null || buttons.Count==0) return;
            float scale=Font.Size/10f; int gap=(int)(8*scale), header=(int)(42*scale), top=(int)(58*scale);
            int width=(ClientSize.Width-gap*(buttons.Count-1))/buttons.Count;
            for(int i=0;i<buttons.Count;i++) {
                buttons[i].SetBounds(i*(width+gap),0,width,header);
                TabPages[i].SetBounds(0,top,ClientSize.Width,Math.Max(0,ClientSize.Height-top));
            }
        }
        protected override void OnLayout(LayoutEventArgs e) { base.OnLayout(e); LayoutPages(); }
        protected override bool ProcessCmdKey(ref Message msg,Keys keyData) {
            if(keyData==(Keys.Control|Keys.Tab) || keyData==(Keys.Control|Keys.Shift|Keys.Tab)) {
                SelectedIndex=(SelectedIndex+((keyData&Keys.Shift)!=0?TabPages.Count-1:1))%TabPages.Count; buttons[SelectedIndex].Focus(); return true;
            }
            return base.ProcessCmdKey(ref msg,keyData);
        }
    }
    public sealed class GameListsForm : DialogForm {
        protected override CreateParams CreateParams {
            get {
                var parameters=base.CreateParams;
                // Each list buffers its own painting. Compositing the entire
                // native child tree adds latency when a tab becomes visible.
                parameters.ExStyle&=~0x02000000; // WS_EX_COMPOSITED
                return parameters;
            }
        }
        internal sealed class GameListView : DialogListView {
            [StructLayout(LayoutKind.Sequential)]
            struct NotifyHeader { public IntPtr Window,Id; public int Code; }
            [StructLayout(LayoutKind.Sequential)]
            struct CustomDraw {
                public NotifyHeader Header;
                public int Stage;
                public IntPtr DC;
                public int Left,Top,Right,Bottom;
                public IntPtr Item;
            }
            // WinForms' Details painter looks up a virtual item several times per
            // cell. Paint its three columns together at CDDS_ITEMPREPAINT.
            bool DrawGameRow(ref Message message) {
                if(Marshal.ReadInt32(message.LParam,2*IntPtr.Size)!=-12 /* NM_CUSTOMDRAW */) return false;
                var draw=(CustomDraw)Marshal.PtrToStructure(message.LParam,typeof(CustomDraw));
                if(draw.Stage!=0x10001 /* CDDS_ITEMPREPAINT */) return false;
                int index=draw.Item.ToInt32();
                if(index<0 || index>=VirtualListSize) return false;
                var item=Items[index];
                bool selected=item.Selected;
                var row=Rectangle.FromLTRB(draw.Left,draw.Top,draw.Right,draw.Bottom);
                int slot=GetItemRect(index,ItemBoundsPortion.Label).Left-row.Left;
                using(var graphics=Graphics.FromHdc(draw.DC))
                using(var brush=new SolidBrush(selected?DialogTheme.Selection:DialogTheme.Surface)) {
                    graphics.FillRectangle(brush,row);
                    var cell=row;
                    for(int column=0;column<Columns.Count;column++) {
                        cell.Width=Columns[column].Width;
                        DialogTheme.DrawListCell(this,graphics,item,column,cell,selected,column==0?slot:0);
                        cell.X+=cell.Width;
                    }
                }
                message.Result=(IntPtr)4; // CDRF_SKIPDEFAULT
                return true;
            }
            public Action<ListViewItem> Toggle;
            public Action<ListViewItem,Point> OpenMenu;
            readonly System.Windows.Forms.Timer singleClickTimer=new System.Windows.Forms.Timer();
            ListViewItem pendingCheck;
            public GameListView() {
                VirtualMode=true; CheckBoxes=true;
                singleClickTimer.Tick+=delegate { CommitSingleClick(); };
            }
            public void CommitSingleClick() {
                singleClickTimer.Stop();
                var item=pendingCheck;
                pendingCheck=null;
                if(item!=null && Toggle!=null) Toggle(item);
            }
            protected override void OnLeave(EventArgs e) {
                CommitSingleClick();
                base.OnLeave(e);
            }
            protected override void Dispose(bool disposing) {
                if(disposing) singleClickTimer.Dispose();
                base.Dispose(disposing);
            }
            // Native virtual lists expose the stored check state, but do not own it.
            // Request the change against the clicked executable on the tray thread.
            protected override void WndProc(ref Message m) {
                if(m.Msg==0x204e /* reflected WM_NOTIFY */ && OwnerDraw && DrawGameRow(ref m)) return;
                if(m.Msg==0x0201 || m.Msg==0x0203 || m.Msg==0x007b) { // left down/double-click, context menu
                    int point=unchecked((int)m.LParam.ToInt64());
                    Point p=new Point((short)point,(short)(point>>16));
                    if(m.Msg==0x007b) {
                        CommitSingleClick();
                        Point local=PointToClient(p);
                        var item=point==-1 ? FocusedItem : ClientRectangle.Contains(local) ? HitTest(local).Item : null;
                        if(item!=null && OpenMenu!=null) {
                            item.Selected=item.Focused=true;
                            OpenMenu(item,point==-1 ? new Point(12,item.Bounds.Bottom) : local);
                        }
                        return;
                    }
                    var hit=HitTest(p);
                    bool onCheck=(hit.Location & ListViewHitTestLocations.StateImage)!=0;
                    if(m.Msg==0x0203) {
                        singleClickTimer.Stop();
                        pendingCheck=null;
                        if(hit.Item!=null && !onCheck) {
                            hit.Item.Selected=hit.Item.Focused=true;
                            OnItemActivate(EventArgs.Empty);
                        }
                        return;
                    }
                    CommitSingleClick();
                    if(hit.Item!=null && onCheck) {
                        Focus();
                        hit.Item.Selected=hit.Item.Focused=true;
                        // The first press of a double-click is an ordinary mouse down.
                        // Wait until Windows has distinguished the two before saving.
                        pendingCheck=hit.Item;
                        singleClickTimer.Interval=SystemInformation.DoubleClickTime;
                        singleClickTimer.Start();
                        return;
                    }
                }
                base.WndProc(ref m);
            }
            protected override void OnKeyDown(KeyEventArgs e) {
                CommitSingleClick();
                if(e.KeyData==Keys.Space && SelectedIndices.Count==1) {
                    e.SuppressKeyPress=true;
                    if(Toggle!=null) Toggle(Items[SelectedIndices[0]]);
                } else base.OnKeyDown(e);
            }
            internal override void FitColumns() {
                if(Columns.Count!=3) return;
                int width=ClientSize.Width;
                int executable=width*44/100, status=width*34/100;
                Columns[0].Width=executable;
                Columns[1].Width=status;
                Columns[2].Width=width-executable-status;
            }
        }
        public readonly Button RefreshButton = new DialogButton();
        public readonly Button RemoveButton = new DialogButton();
        public event Action<string,bool> EnableRequested;
        internal bool AllowToggle=true;
        public bool CanRemoveSelected { get {
            int i=tabs.SelectedIndex;
            return !String.IsNullOrEmpty(SelectedExecutable) && (bool)rows[i][lists[i].SelectedIndices[0]].Tag;
        } }
        public readonly Button EditCustomButton = new DialogButton();
        public readonly Button UpdateCommunityButton = new DialogButton();
        public readonly CheckBox UseCommunityApps = new DialogCheckBox { Text="Use community app list" };
        public readonly Button AddRunningButton = new DialogButton(), AddGameButton = new DialogButton(), EditRuleButton = new DialogButton(), LaunchButton = new DialogButton(), ShortcutButton = new DialogButton();
        public string SelectedExecutable { get {
            int index=tabs.SelectedIndex;
            if(index<0 || index>=lists.Length || lists[index]==null) return "";
            var selected=lists[index].SelectedIndices;
            return selected.Count==1 && selected[0]<rows[index].Count ? rows[index][selected[0]].Text : "";
        } }
        readonly DialogTabs tabs = new DialogTabs();
        readonly string[] sections = { "Auto-detected", "Defaults", "Custom" };
        readonly int[] enabledCounts = new int[3];
        readonly GameListView[] lists = new GameListView[3];
        readonly string[] savedSelection=new string[3];
        readonly int[] savedTop=new int[3];
        readonly ContextMenuStrip itemMenu=new ContextMenuStrip();
        readonly System.Collections.Generic.List<ListViewItem>[] rows = new System.Collections.Generic.List<ListViewItem>[3];
        readonly Label[] emptyStates = new Label[3];

        public GameListsForm() : this(null) { }
        internal GameListsForm(Panel footer) {
            Text="Game lists"; Font=new Font("Segoe UI",10);
            AutoScaleDimensions=new SizeF(96,96); AutoScaleMode=AutoScaleMode.Dpi;
            ClientSize=new Size(880,footer==null?660:660-SettingsFooterHeight); MinimumSize=footer==null?new Size(896,699):Size.Empty;
            StartPosition=FormStartPosition.CenterScreen;
            DialogTheme.AddSettingsHeader(this,Text,"Check a game to enable automatic HDR. Right-click it for more actions.");
            itemMenu.Renderer=new TrayMenuRenderer(); itemMenu.ShowImageMargin=false;
            itemMenu.Font=Font; itemMenu.MinimumSize=new Size(180,0);
            var toggle=itemMenu.Items.Add("Disable game");
            itemMenu.Items.Add(new ToolStripSeparator());
            foreach(var button in new Button[]{EditRuleButton,LaunchButton,ShortcutButton,RemoveButton}) {
                var action=button;
                itemMenu.Items.Add("",null,delegate {action.PerformClick();});
            }
            toggle.Click+=delegate {
                var list=lists[tabs.SelectedIndex];
                if(list.SelectedIndices.Count==1) list.Toggle(list.Items[list.SelectedIndices[0]]);
            };
            Disposed+=delegate {itemMenu.Dispose();};
            tabs.SetBounds(24,166,832,308);
            tabs.Anchor=AnchorStyles.Top|AnchorStyles.Bottom|AnchorStyles.Left|AnchorStyles.Right;
            for (int i=0;i<sections.Length;i++) {
                var page=new Panel {Text=sections[i],Padding=new Padding(12)};
                int section=i;
                rows[i]=new System.Collections.Generic.List<ListViewItem>();
                var list=new GameListView { Dock=DockStyle.Fill, View=View.Details,
                    FullRowSelect=true, HideSelection=false, MultiSelect=false, AccessibleName=sections[i]+" games" };
                // Hidden tabs otherwise insert every native item on their first
                // handle creation. Virtual lists request only the visible rows.
                list.RetrieveVirtualItem+=delegate(object sender,RetrieveVirtualItemEventArgs e) { e.Item=rows[section][e.ItemIndex]; };
                list.SearchForVirtualItem+=delegate(object sender,SearchForVirtualItemEventArgs e) {
                    if(!e.IsTextSearch || rows[section].Count==0) return;
                    int count=rows[section].Count, start=Math.Max(0,e.StartIndex)%count;
                    for(int offset=0;offset<count;offset++) {
                        int index=(start+offset)%count;
                        var item=rows[section][index];
                        int columns=e.IncludeSubItemsInSearch ? item.SubItems.Count : 1;
                        for(int column=0;column<columns;column++) {
                            string text=item.SubItems[column].Text;
                            if(e.IsPrefixSearch ? text.StartsWith(e.Text,StringComparison.OrdinalIgnoreCase) : String.Equals(text,e.Text,StringComparison.OrdinalIgnoreCase)) { e.Index=index; return; }
                        }
                    }
                };
                list.Columns.Add("Executable"); list.Columns.Add("Status"); list.Columns.Add("First detected");
                list.Toggle=delegate(ListViewItem item) {
                    if(!AllowToggle || EnableRequested==null) return;
                    // A refresh can replace the virtual items during the double-click interval.
                    int at=rows[section].FindIndex(row=>String.Equals(row.Text,item.Text,StringComparison.OrdinalIgnoreCase));
                    if(at<0) return;
                    item=rows[section][at];
                    var updated=(ListViewItem)item.Clone();
                    updated.Checked=!item.Checked;
                    rows[section][at]=updated;
                    enabledCounts[section]+=updated.Checked ? 1 : -1;
                    UpdateSectionCaption(section);
                    list.RedrawItems(at,at,false);
                    EnableRequested(updated.Text,updated.Checked);
                };
                list.OpenMenu=delegate(ListViewItem item,Point position) {
                    toggle.Text=item.Checked?"Disable game":"Enable game";
                    toggle.Enabled=AllowToggle;
                    int n=2;
                    foreach(var action in new Button[]{EditRuleButton,LaunchButton,ShortcutButton,RemoveButton}) {
                        itemMenu.Items[n].Text=action.Text; itemMenu.Items[n++].Enabled=action.Enabled;
                    }
                    itemMenu.Show(list,position);
                };
                list.ItemActivate+=delegate { if(EditRuleButton.Enabled) EditRuleButton.PerformClick(); };
                list.FitColumns();
                lists[i]=list; page.Controls.Add(list); tabs.TabPages.Add(page);
                string[] hints={"No games detected yet.\r\nKnown games appear here while auto-enable HDR is on.","No community games to show.\r\nUpdate the community list to check for games.","Your custom list is empty.\r\nChoose Add game or Add running game to get started."};
                var empty=new Label {Text=hints[i],TextAlign=ContentAlignment.MiddleCenter,Dock=DockStyle.Fill,Tag="muted"};
                emptyStates[i]=empty; list.Controls.Add(empty);
            }
            RefreshButton.Text="Refresh"; RefreshButton.SetBounds(24,110,100,38);
            UseCommunityApps.SetBounds(140,110,220,38);
            AddRunningButton.Text="Add running game"; AddRunningButton.SetBounds(546,110,170,38);
            AddGameButton.Text="Add game"; AddGameButton.SetBounds(726,110,130,38);
            ((DialogButton)AddGameButton).Primary=true;
            EditRuleButton.Text="Game settings"; EditRuleButton.SetBounds(24,492,170,38);
            LaunchButton.Text="Launch with HDR"; LaunchButton.SetBounds(204,492,170,38);
            ShortcutButton.Text="Create shortcut"; ShortcutButton.SetBounds(384,492,170,38);
            RemoveButton.Text="Remove game"; RemoveButton.SetBounds(564,492,150,38);
            RemoveButton.AccessibleDescription="Remove a local entry or detection. To turn off a community default, uncheck its row.";
            if(footer==null) footer=CreateSettingsFooter();
            UpdateCommunityButton.Text="Update community list"; UpdateCommunityButton.SetBounds(24,12,220,38);
            EditCustomButton.Text="Edit custom list"; EditCustomButton.SetBounds(254,12,160,38);
            footer.Controls.AddRange(new Control[]{UpdateCommunityButton,EditCustomButton});
            foreach(var button in new Button[]{RefreshButton,AddRunningButton,AddGameButton,EditRuleButton,LaunchButton,ShortcutButton,RemoveButton}) {
                button.Anchor=AnchorStyles.Bottom|AnchorStyles.Left; Controls.Add(button);
            }
            RefreshButton.Anchor=AnchorStyles.Top|AnchorStyles.Left;
            AddRunningButton.Anchor=AddGameButton.Anchor=AnchorStyles.Top|AnchorStyles.Right;
            var note=DialogTheme.Caption("Remove game clears local entries. To turn off a community default, uncheck its row.",24,540,832,38);
            note.Anchor=AnchorStyles.Bottom|AnchorStyles.Left|AnchorStyles.Right;
            Controls.AddRange(new Control[] {UseCommunityApps,tabs,note});
            foreach(var list in lists) list.SelectedIndexChanged+=delegate { UpdateActions(); };
            tabs.SelectedIndexChanged+=delegate { UpdateActions(); };
            DialogTheme.Apply(this);
            FormClosing+=delegate { CommitPendingClicks(); };
            FinishRows();
        }
        internal void CommitPendingClicks() { foreach(var list in lists) list.CommitSingleClick(); }
        void UpdateActions() {
            EditRuleButton.Enabled=LaunchButton.Enabled=ShortcutButton.Enabled=!String.IsNullOrEmpty(SelectedExecutable);
            RemoveButton.Enabled=CanRemoveSelected;
        }
        public void ClearRows() {
            itemMenu.Close();
            for(int i=0;i<lists.Length;i++) {
                var indices=lists[i].SelectedIndices;
                savedSelection[i]=indices.Count==1 ? rows[i][indices[0]].Text : null;
                savedTop[i]=lists[i].IsHandleCreated && rows[i].Count>0 && lists[i].TopItem!=null ? lists[i].TopItem.Index : 0;
                lists[i].BeginUpdate(); lists[i].SelectedIndices.Clear(); lists[i].VirtualListSize=0; rows[i].Clear();
                enabledCounts[i]=0;
            }
        }
        public void AddRow(string section, string executable, string status, string detected,bool enabled=true,bool canRemove=true) {
            int index=Array.IndexOf(sections,section);
            if (index<0) throw new ArgumentException("Unknown game list section.");
            rows[index].Add(new ListViewItem(new string[] {executable,status,detected}) {Checked=enabled,Tag=canRemove});
            if(enabled) enabledCounts[index]++;
        }
        void UpdateSectionCaption(int index) {
            tabs.TabPages[index].Text=sections[index]+" ("+enabledCounts[index]+"/"+rows[index].Count+")";
        }
        public void FinishRows() {
            for (int i=0;i<lists.Length;i++) {
                lists[i].VirtualListSize=rows[i].Count;
                lists[i].EndUpdate(); UpdateSectionCaption(i);
                lists[i].FitColumns();
                if(savedSelection[i]!=null) {
                    int at=rows[i].FindIndex(item=>String.Equals(item.Text,savedSelection[i],StringComparison.OrdinalIgnoreCase));
                    if(at>=0) {lists[i].SelectedIndices.Add(at); lists[i].Items[at].Focused=true;}
                }
                if(savedTop[i]>0 && rows[i].Count>0) lists[i].TopItem=lists[i].Items[Math.Min(savedTop[i],rows[i].Count-1)];
                emptyStates[i].Visible=rows[i].Count==0;
            }
            UpdateActions();
        }
    }
    public static class NightLightReader {
        public static bool? Decode(byte[] data) {
            if(data==null || data.Length<12 || data.Length>4096) return null;
            bool recognized=false;
            // Recognize the known CloudStore state record only. Future layouts
            // must use the schedule fallback rather than guessing a state.
            for(int i=0;i<=data.Length-4;i++) {
                if(data[i]!=0x43 || data[i+1]!=0x42 || data[i+2]!=1 || data[i+3]!=0) continue;
                recognized=true;
                for(int j=i+4;j+1<Math.Min(data.Length,i+14);j++)
                    if(data[j]==0x10 && data[j+1]==0) return true;
            }
            return recognized?(bool?)false:null;
        }
        public static bool? Read() {
            string root=@"Software\Microsoft\Windows\CurrentVersion\CloudStore\Store\";
            string leaf=@"default$windows.data.bluelightreduction.bluelightreductionstate\windows.data.bluelightreduction.bluelightreductionstate";
            foreach(string path in new string[] {root+@"DefaultAccount\Current\"+leaf,root+@"DefaultAccount\Cloud\"+leaf,
                root+@"Cache\DefaultAccount\$$windows.data.bluelightreduction.bluelightreductionstate\Current"}) {
                try {
                    using(var key=Microsoft.Win32.Registry.CurrentUser.OpenSubKey(path)) {
                        bool? result=Decode(key==null?null:key.GetValue("Data") as byte[]);
                        if(result.HasValue) return result;
                    }
                } catch(System.Security.SecurityException) { } catch(UnauthorizedAccessException) { } catch(System.IO.IOException) { }
            }
            return null;
        }
    }
    public sealed class BrightnessLocationFix {
        public readonly double Latitude,Longitude;
        public readonly DateTime CapturedUtc;
        public BrightnessLocationFix(double latitude,double longitude,DateTime capturedUtc) {
            if(Double.IsNaN(latitude) || Double.IsNaN(longitude) || Math.Abs(latitude)>90 || Math.Abs(longitude)>180)
                throw new ArgumentOutOfRangeException("latitude");
            Latitude=latitude; Longitude=longitude; CapturedUtc=capturedUtc;
        }
    }
    public static class BrightnessLocation {
        public static string HelperPath { private get; set; }
        static readonly object gate=new object();
        static BrightnessLocationFix fix;
        static DateTime nextRead=DateTime.MinValue;
        static bool reading;
        static string status="Location has not been requested.";
        public static string Status { get { lock(gate) return status; } }
        public static BrightnessLocationFix Current {
            get { lock(gate) return fix!=null && DateTime.UtcNow-fix.CapturedUtc<TimeSpan.FromHours(1)?fix:null; }
        }
        public static void Request(bool refresh) {
            lock(gate) {
                if(reading || (!refresh && DateTime.UtcNow<nextRead)) return;
                reading=true; status="Finding your Windows location...";
            }
            ThreadPool.QueueUserWorkItem(delegate {
                BrightnessLocationFix found=null;
                string message="Location unavailable. Check Windows location settings.";
                try {
                    var start=new System.Diagnostics.ProcessStartInfo(HelperPath,"--read-location") {
                        UseShellExecute=false, CreateNoWindow=true, RedirectStandardOutput=true
                    };
                    using(var process=System.Diagnostics.Process.Start(start)) {
                        if(!process.WaitForExit(15000)) process.Kill();
                        else if(process.ExitCode==0) {
                            using(var result=new System.IO.BinaryReader(process.StandardOutput.BaseStream)) {
                                double latitude=result.ReadDouble(), longitude=result.ReadDouble();
                                var captured=new DateTime(result.ReadInt64(),DateTimeKind.Utc);
                                var now=DateTime.UtcNow;
                                if(now-captured<TimeSpan.FromHours(1) && captured<=now.AddMinutes(1)) {
                                    found=new BrightnessLocationFix(latitude,longitude,captured);
                                    message="Windows location ready. Times are calculated on this PC.";
                                }
                            }
                        }
                    }
                } catch(Exception) { /* No IP lookup or guessed location when Windows denies access. */ }
                finally {
                    lock(gate) {
                        fix=found; status=message; reading=false;
                        nextRead=DateTime.UtcNow.AddMinutes(found==null?5:30);
                    }
                }
            });
        }
    }
    public static class BrightnessSun {
        // NOAA fractional-year solar position, with the standard -0.833 degree horizon.
        // https://gml.noaa.gov/grad/solcalc/solareqns.PDF
        public static bool IsDay(DateTime utc,double latitude,double longitude) {
            if(Double.IsNaN(latitude) || Double.IsNaN(longitude) || Math.Abs(latitude)>90 || Math.Abs(longitude)>180)
                throw new ArgumentOutOfRangeException("latitude");
            double radians=Math.PI/180;
            double year=2*Math.PI/(DateTime.IsLeapYear(utc.Year)?366:365)*(utc.DayOfYear-1+(utc.TimeOfDay.TotalHours-12)/24);
            double equation=229.18*(.000075+.001868*Math.Cos(year)-.032077*Math.Sin(year)-.014615*Math.Cos(2*year)-.040849*Math.Sin(2*year));
            double decl=.006918-.399912*Math.Cos(year)+.070257*Math.Sin(year)-.006758*Math.Cos(2*year)+.000907*Math.Sin(2*year)-.002697*Math.Cos(3*year)+.00148*Math.Sin(3*year);
            double angle=(utc.TimeOfDay.TotalMinutes+equation+4*longitude)/4-180;
            double altitude=Math.Sin(latitude*radians)*Math.Sin(decl)+Math.Cos(latitude*radians)*Math.Cos(decl)*Math.Cos(angle*radians);
            return altitude>=Math.Sin(-.833*radians);
        }
        public static DateTime? Crossing(DateTime localDate,double latitude,double longitude,TimeZoneInfo zone,bool sunrise) {
            // Scan UTC and filter the local result. Some zones skip/repeat local midnight.
            var start=DateTime.SpecifyKind(localDate.Date,DateTimeKind.Utc).AddHours(-14);
            var end=DateTime.SpecifyKind(localDate.Date.AddDays(1),DateTimeKind.Utc).AddHours(14);
            bool previous=IsDay(start,latitude,longitude);
            for(var instant=start.AddMinutes(5);instant<=end;instant=instant.AddMinutes(5)) {
                bool current=IsDay(instant,latitude,longitude);
                if(current!=previous && current==sunrise) {
                    var lo=instant.AddMinutes(-5); var hi=instant;
                    while((hi-lo).TotalSeconds>1) {
                        var middle=lo.AddTicks((hi-lo).Ticks/2);
                        if(IsDay(middle,latitude,longitude)==current) hi=middle; else lo=middle;
                    }
                    var local=TimeZoneInfo.ConvertTimeFromUtc(hi,zone);
                    if(local.Date==localDate.Date) return local;
                }
                previous=current;
            }
            return null;
        }
    }
    public sealed class BrightnessCard : Panel {
        public BrightnessCard() { DoubleBuffered=true; }
        protected override void OnPaintBackground(PaintEventArgs e) {
            if(SystemInformation.HighContrast) { base.OnPaintBackground(e); return; }
            e.Graphics.Clear(DialogTheme.Background); e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
            using(var shape=DialogTheme.Round(new RectangleF(0,0,Width-1,Height-1),10))
            using(var fill=new SolidBrush(DialogTheme.Surface)) e.Graphics.FillPath(fill,shape);
        }
    }
    public sealed class BrightnessTimeInput : UserControl {
        public readonly MaskedTextBox Editor=new MaskedTextBox("00:00");
        readonly DialogButton increase=new DialogButton(),decrease=new DialogButton();
        Font editorFont;
        public BrightnessTimeInput() {
            DoubleBuffered=true; Size=new Size(250,44); TabStop=false;
            Editor.BorderStyle=BorderStyle.None; Editor.TextAlign=HorizontalAlignment.Center;
            UpdateEditorFont(); Editor.AccessibleName="Time in 24-hour format";
            increase.Text="+"; decrease.Text="\u2212";
            increase.StepGlyph=1; decrease.StepGlyph=-1;
            increase.AccessibleName="Increase selected hour or minute"; decrease.AccessibleName="Decrease selected hour or minute";
            Controls.AddRange(new Control[]{Editor,decrease,increase});
            increase.Click+=delegate { Step(1); }; decrease.Click+=delegate { Step(-1); };
            Editor.KeyDown+=delegate(object sender,KeyEventArgs e) {
                if(e.KeyCode==Keys.Up || e.KeyCode==Keys.Down) { Step(e.KeyCode==Keys.Up?1:-1); e.SuppressKeyPress=true; }
            };
            Editor.Enter+=delegate { Editor.AccessibleName=AccessibleName+", 24-hour time"; Invalidate(); }; Editor.Leave+=delegate { Invalidate(); };
            Value=DateTime.Today; LayoutInput();
        }
        public override string Text { get { return Editor==null?"":Editor.Text; } set { if(Editor!=null) Editor.Text=value; } }
        public void Step(int direction) {
            int selected=Editor.SelectionStart<3?0:3;
            DateTime time;
            try { time=Value; } catch(FormatException) { System.Media.SystemSounds.Beep.Play(); return; }
            Value=selected==0?time.AddHours(direction):time.AddMinutes(direction);
            Editor.Focus(); Editor.Select(selected,2);
        }
        void LayoutInput() {
            if(Editor==null) return;
            float scale=Font.Size/10f; int side=(int)(32*scale),pad=(int)(8*scale);
            decrease.SetBounds(Width-2*side-pad, pad/2,side,Height-pad);
            increase.SetBounds(Width-side-pad/2,pad/2,side,Height-pad);
            Editor.SetBounds(pad,Math.Max(2,(Height-Editor.PreferredHeight)/2),Math.Max(30,Width-2*side-3*pad),Editor.PreferredHeight);
        }
        protected override void OnResize(EventArgs e) { base.OnResize(e); LayoutInput(); }
        void UpdateEditorFont() {
            if(Editor==null) return;
            var previous=editorFont; editorFont=new Font("Segoe UI Semibold",Font.Size*1.6f);
            Editor.Font=editorFont; if(previous!=null) previous.Dispose();
        }
        protected override void OnFontChanged(EventArgs e) { base.OnFontChanged(e); UpdateEditorFont(); LayoutInput(); }
        protected override void Dispose(bool disposing) { base.Dispose(disposing); if(disposing && editorFont!=null) { editorFont.Dispose(); editorFont=null; } }
        protected override void OnEnabledChanged(EventArgs e) { base.OnEnabledChanged(e); Invalidate(); }
        protected override void OnPaintBackground(PaintEventArgs e) {
            if(SystemInformation.HighContrast) { base.OnPaintBackground(e); return; }
            // Outside the rounded field, reveal the card; child button corners
            // use this control's BackColor to blend into the field itself.
            e.Graphics.Clear(Parent==null?DialogTheme.Background:Parent.BackColor);
        }
        protected override void OnPaint(PaintEventArgs e) {
            base.OnPaint(e); e.Graphics.SmoothingMode=SmoothingMode.AntiAlias;
            var fill=SystemInformation.HighContrast?SystemColors.Window:DialogTheme.Background;
            Editor.BackColor=fill;
            Editor.ForeColor=SystemInformation.HighContrast?SystemColors.WindowText:Enabled?DialogTheme.Text:DialogTheme.Muted;
            using(var shape=DialogTheme.Round(new RectangleF(1,1,Width-3,Height-3),8*Font.Size/10f))
            using(var brush=new SolidBrush(fill))
            using(var pen=new Pen(SystemInformation.HighContrast?SystemColors.WindowText:ContainsFocus?DialogTheme.Accent:DialogTheme.Border)) {
                e.Graphics.FillPath(brush,shape); e.Graphics.DrawPath(pen,shape);
            }
        }
        public DateTime Value {
            get {
                DateTime time;
                if(!DateTime.TryParseExact(Text,"HH:mm",System.Globalization.CultureInfo.InvariantCulture,System.Globalization.DateTimeStyles.None,out time))
                    throw new FormatException("Enter a valid time in HH:mm format, for example 08:00 or 18:30.");
                return time;
            }
            set { Text=value.ToString("HH:mm",System.Globalization.CultureInfo.InvariantCulture); }
        }
    }
    public sealed class SdrBrightnessForm : DialogForm {
        public string DisplayId;
        public string PreferenceKey;
        public uint SelectedLevel;
        public bool CanAdjust;
        public bool LevelEdited;
        public uint DayLevel, NightLevel;
        uint readoutLevel;
        public readonly TrackBar DaySlider=new DialogSlider(), NightSlider=new DialogSlider();
        public readonly DialogComboBox Switching=new DialogComboBox();
        public readonly BrightnessTimeInput DayStart=new BrightnessTimeInput(), NightStart=new BrightnessTimeInput();
        public readonly CheckBox Enforce=new DialogCheckBox();
        public readonly Button Calibrate=new DialogButton(), HdrSettings=new DialogButton(), NightLightSettings=new DialogButton();
        public readonly Button LocationSettings=new DialogButton(), RefreshLocation=new DialogButton();
        public readonly Label LocationStatus=new Label();
        public readonly Label Runtime=new Label();
        public readonly Panel Body=new Panel(), Footer=new Panel();
        readonly Label dayValue=new Label(),nightValue=new Label(),scheduleHint=new Label();
        readonly Label dayLabel=new Label(),nightLabel=new Label();
        readonly TableLayoutPanel levelColumn=SettingsColumn(), standaloneRows=SettingsColumn();
        readonly TableLayoutPanel periods=new TableLayoutPanel();
        readonly TableLayoutPanel sliderRows=SettingsColumn();
        readonly BrightnessCard sliderCard=new BrightnessCard {Size=new Size(552,30),Padding=new Padding(8,0,8,0)};
        readonly BrightnessCard switchingCard;
        readonly Label readoutTitle=new Label();
        readonly System.Windows.Forms.Timer locationTimer=new System.Windows.Forms.Timer();
        readonly System.Windows.Forms.Timer saveTimer=new System.Windows.Forms.Timer {Interval=300};
        internal Guid EditId { get; private set; }
        bool savingDisplay;
        internal event Action SettingsEdited;
        string validationMessage,availabilityMessage;
        DateTime validDayStart=DateTime.Today.AddHours(8),validNightStart=DateTime.Today.AddHours(18);
        bool locationExpanded;
        string solarSummary="",solarKey="";
        bool busy, hdrOff;
        public string SwitchingMode { get { return Switching.ValueIndex==1?"Schedule":Switching.ValueIndex==2?"NightLight":Switching.ValueIndex==3?"SunriseSunset":"Manual"; } }
        public readonly TrackBar Slider = new DialogSlider();
        public readonly CheckBox Restore = new DialogCheckBox();
        internal readonly SaveStatusLabel SaveStatus=new SaveStatusLabel();
        public Label Status { get { return SaveStatus; } }
        readonly Label value = new Label();
        bool initializing = true;

        public SdrBrightnessForm(string name, string displayId, string preferenceKey, uint level, bool restore) {
            EditId=Guid.NewGuid();
            DisplayId=displayId; PreferenceKey=preferenceKey; SelectedLevel=level; readoutLevel=level;
            Text="SDR brightness"; Font=new Font("Segoe UI",10);
            AutoScaleDimensions=new SizeF(96,96); AutoScaleMode=AutoScaleMode.Dpi;
            ClientSize=new Size(600,906); FormBorderStyle=FormBorderStyle.FixedDialog;
            MaximizeBox=false; MinimizeBox=false; StartPosition=FormStartPosition.CenterScreen;
            Body.Dock=DockStyle.Fill; Body.AutoScroll=true;
            Footer.Dock=DockStyle.Bottom; Footer.Height=64;
            Controls.Add(Body); Controls.Add(Footer);
            var title=DialogTheme.Heading("SDR brightness",0,0,530);
            var monitor=DialogTheme.Caption(name,0,0,530,26); monitor.AutoEllipsis=true;
            var readout=new TableLayoutPanel {Size=new Size(552,66),ColumnCount=2,RowCount=1};
            readout.RowStyles.Add(new RowStyle(SizeType.Percent,100));
            readout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
            readout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
            value.AutoSize=true; value.Font=new Font("Segoe UI Semibold",26);
            value.Margin=new Padding(0,0,12,0);
            var caption=new Panel {Dock=DockStyle.Fill,Margin=Padding.Empty};
            readoutTitle.SetBounds(0,2,300,22); readoutTitle.AutoSize=true; readoutTitle.Font=new Font("Segoe UI Semibold",11);
            Runtime.Dock=DockStyle.Bottom; Runtime.Height=40; Runtime.Tag="muted"; Runtime.AutoEllipsis=true;
            caption.Controls.AddRange(new Control[]{readoutTitle,Runtime});
            readout.Controls.Add(value,0,0); readout.Controls.Add(caption,1,0);
            Slider.Dock=DockStyle.Fill;
            sliderCard.Controls.Add(Slider);
            Slider.Minimum=0; Slider.Maximum=100;
            Slider.TickStyle=TickStyle.None; Slider.LargeChange=10;
            Slider.AccessibleName="SDR content brightness";
            Slider.Value=LevelPercent(level);
            Slider.ValueChanged += delegate { if (!initializing) { SelectedLevel=(uint)(1000+50*Slider.Value); LevelEdited=true; } UpdateValue(); };
            periods.Size=new Size(552,126); periods.ColumnCount=2; periods.RowCount=1;
            periods.RowStyles.Add(new RowStyle(SizeType.Percent,100));
            periods.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,50));
            periods.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,50));
            var dayCard=PeriodCard("Day","\u263c",DaySlider,dayValue);
            var nightCard=PeriodCard("Night","\u263e",NightSlider,nightValue);
            dayCard.Margin=new Padding(0,0,5,0); nightCard.Margin=new Padding(5,0,0,0);
            periods.Controls.Add(dayCard,0,0); periods.Controls.Add(nightCard,1,0);
            DayLevel=NightLevel=level;
            DaySlider.Value=NightSlider.Value=Slider.Value;
            DaySlider.ValueChanged+=delegate { if(!initializing) DayLevel=(uint)(1000+50*DaySlider.Value); UpdateValue(); };
            NightSlider.ValueChanged+=delegate { if(!initializing) NightLevel=(uint)(1000+50*NightSlider.Value); UpdateValue(); };
            var switching=switchingCard=new BrightnessCard {Size=new Size(552,204)};
            switching.Controls.Add(new Label {Text="Switching",Font=new Font("Segoe UI Semibold",11),Location=new Point(16,12),AutoSize=true});
            Switching.Items.AddRange(new object[]{"Manual","Custom schedule","Follow Windows Night Light","Sunrise & sunset (location)"});
            Switching.SetBounds(16,42,520,34); Switching.SelectedIndex=0;
            Switching.SelectedIndexChanged+=delegate {
                if(!initializing && Switching.SelectedIndex==0) {
                    // Manual mode disables the time fields. Discard an invalid time draft.
                    try { RememberScheduleTimes(); }
                    catch(FormatException) { DayStart.Value=validDayStart; NightStart.Value=validNightStart; }
                }
                RefreshControls(); UpdateValue();
            };
            dayLabel.Text="Day starts"; dayLabel.SetBounds(16,84,250,24);
            nightLabel.Text="Night starts"; nightLabel.SetBounds(286,84,250,24);
            dayLabel.Tag=nightLabel.Tag="muted";
            DayStart.SetBounds(16,110,250,46); NightStart.SetBounds(286,110,250,46);
            DayStart.Value=DateTime.Today.AddHours(8); NightStart.Value=DateTime.Today.AddHours(18);
            DayStart.AccessibleName="Day starts"; NightStart.AccessibleName="Night starts";
            scheduleHint.SetBounds(16,164,520,34); scheduleHint.Tag="muted";
            LocationStatus.SetBounds(16,202,520,38); LocationStatus.Tag="muted";
            RefreshLocation.Text="Refresh location"; RefreshLocation.SetBounds(16,248,250,32);
            LocationSettings.Text="Windows location settings"; LocationSettings.SetBounds(286,248,250,32);
            RefreshLocation.Click+=delegate { BrightnessLocation.Request(true); RefreshLocationStatus(); };
            switching.Controls.AddRange(new Control[]{Switching,dayLabel,DayStart,nightLabel,NightStart,scheduleHint,LocationStatus,RefreshLocation,LocationSettings});
            var behavior=new Panel {Size=new Size(552,96)};
            behavior.Controls.Add(new Label {Text="Restore brightness",Font=new Font("Segoe UI Semibold",11),AutoSize=true,Location=new Point(0,2)});
            Restore.Text="When HDR turns on";
            Restore.SetBounds(0,28,552,30); Restore.Checked=restore;
            Restore.Enabled=!String.IsNullOrEmpty(preferenceKey) && level>=1000 && level<=6000;
            Enforce.Text="After brightness is changed elsewhere"; Enforce.SetBounds(0,60,552,30);
            Restore.Anchor=Enforce.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right;
            behavior.Controls.AddRange(new Control[]{Restore,Enforce});
            AddSettingsRow(sliderRows,sliderCard);
            AddSettingsRow(sliderRows,periods);
            foreach(Control c in new Control[]{readout,sliderRows,Status,behavior}) AddSettingsRow(levelColumn,c);
            sliderRows.Margin=Padding.Empty;
            Calibrate.Text="Windows HDR Calibration";
            HdrSettings.Text="Windows HDR settings";
            HdrSettings.Height=36;
            NightLightSettings.Text="Night Light settings";
            Status.Height=48; Status.AutoEllipsis=false;
            var shortcuts=new TableLayoutPanel {Size=new Size(552,36),ColumnCount=2,RowCount=1};
            shortcuts.RowStyles.Add(new RowStyle(SizeType.Percent,100));
            shortcuts.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,50)); shortcuts.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,50));
            Calibrate.Dock=NightLightSettings.Dock=DockStyle.Fill;
            Calibrate.Margin=new Padding(0,0,6,0); NightLightSettings.Margin=new Padding(6,0,0,0);
            shortcuts.Controls.Add(Calibrate,0,0); shortcuts.Controls.Add(NightLightSettings,1,0);
            standaloneRows.Padding=new Padding(16,16,16,0);
            foreach(Control c in new Control[]{title,monitor,levelColumn,switching,shortcuts,HdrSettings}) AddSettingsRow(standaloneRows,c);
            Body.Controls.Add(standaloneRows);
            var close=new DialogButton { Text="Close", Bounds=new Rectangle(462,14,114,36), Anchor=AnchorStyles.Top|AnchorStyles.Right, DialogResult=DialogResult.Cancel };
            close.Click += delegate { CloseSettings(); };
            CancelButton=close;
            Status.Tag="muted";
            Footer.Controls.Add(close);
            DialogTheme.Apply(this);
            foreach(Control card in new Control[]{sliderCard,dayCard,nightCard,switching}) if(!SystemInformation.HighContrast) {
                card.BackColor=DialogTheme.Surface;
                foreach(Control child in card.Controls) child.BackColor=child is BrightnessTimeInput?DialogTheme.Background:DialogTheme.Surface;
            }
            if(!SystemInformation.HighContrast) value.ForeColor=DialogTheme.Accent;
            foreach(var slider in new[]{Slider,DaySlider,NightSlider}) {
                slider.ValueChanged+=QueueSave;
                slider.MouseCaptureChanged+=delegate { if(!slider.Capture) CommitEdits(); };
            }
            DayStart.Editor.TextChanged+=QueueSave; NightStart.Editor.TextChanged+=QueueSave;
            Restore.CheckedChanged+=QueueSave; Enforce.CheckedChanged+=QueueSave;
            Switching.SelectedIndexChanged+=QueueSave;
            saveTimer.Tick+=delegate { if(!Slider.Capture && !DaySlider.Capture && !NightSlider.Capture) CommitEdits(); };
            initializing=false; UpdateValue(); RefreshControls();
            locationTimer.Interval=1000; locationTimer.Tick+=delegate { if(Visible && SwitchingMode=="SunriseSunset") RefreshLocationStatus(); };
            Shown+=delegate { locationTimer.Start(); };
            Disposed+=delegate { locationTimer.Dispose(); saveTimer.Dispose(); };
            Load+=delegate { var area=Screen.FromControl(this).WorkingArea; if(TopLevel && Height>area.Height-24) { Height=Math.Max(400,area.Height-24); Top=area.Top+12; } };
        }
        void QueueSave(object sender,EventArgs e) {
            if(initializing || SettingsEdited==null) return;
            // Ignore acknowledgements for an older edit, even if only a checkbox or time changed.
            EditId=Guid.NewGuid();
            SaveStatus.ClearFeedback();
            saveTimer.Stop();
            saveTimer.Start();
        }
        void RememberScheduleTimes() {
            var day=DayStart.Value; var night=NightStart.Value;
            if(day.TimeOfDay==night.TimeOfDay) throw new FormatException("Day and night must start at different times.");
            validDayStart=day; validNightStart=night;
        }
        internal void CommitEdits() {
            if(!saveTimer.Enabled) return;
            saveTimer.Stop();
            try {
                RememberScheduleTimes();
                validationMessage=null;
                SettingsEdited();
            } catch(FormatException error) { validationMessage=error.Message; }
            SaveStatus.SetIdleText(validationMessage ?? availabilityMessage);
        }
        // The shared window has room for two columns. Keep the same controls and
        // validation as the narrow editor and let each column wrap independently.
        internal void UseSettingsLayout() {
            Body.SuspendLayout();
            Footer.Hide(); CancelButton=null;
            var columns=new TableLayoutPanel {Dock=DockStyle.Top,AutoSize=true,ColumnCount=2,RowCount=1,Padding=new Padding(22,4,22,4)};
            var left=levelColumn; var right=SettingsColumn();
            left.Margin=new Padding(0,0,7,0); right.Margin=new Padding(7,0,0,0);
            columns.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,50));
            columns.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,50));
            columns.Controls.Add(left,0,0); columns.Controls.Add(right,1,0);
            foreach(Control c in new Control[]{Switching,scheduleHint,LocationStatus})
                c.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right;
            LocationSettings.Text="Location settings";
            switchingCard.SizeChanged+=delegate {
                int pad=Switching.Left, gap=pad, half=(Switching.Width-gap)/2;
                foreach(Control c in new Control[]{dayLabel,DayStart,RefreshLocation}) c.Width=half;
                foreach(Control c in new Control[]{nightLabel,NightStart,LocationSettings}) {
                    c.Left=pad+half+gap; c.Width=Switching.Width-half-gap;
                }
            };
            Calibrate.Dock=NightLightSettings.Dock=DockStyle.None;
            Calibrate.Height=NightLightSettings.Height=36;
            foreach(Control c in new Control[]{switchingCard,Calibrate,HdrSettings,NightLightSettings}) AddSettingsRow(right,c);
            Body.Controls.Add(columns);
            standaloneRows.Dispose();
            Body.ResumeLayout(true);
        }
        static TableLayoutPanel SettingsColumn() {
            var column=new TableLayoutPanel {AutoSize=true,ColumnCount=1,Dock=DockStyle.Top};
            column.ColumnStyles.Add(new ColumnStyle(SizeType.Percent,100));
            return column;
        }
        static void AddSettingsRow(TableLayoutPanel column,Control control) {
            control.Margin=new Padding(0,0,0,12);
            control.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right;
            column.RowStyles.Add(new RowStyle(SizeType.AutoSize));
            column.Controls.Add(control,0,column.RowCount++);
        }
        static BrightnessCard PeriodCard(string label,string glyph,TrackBar slider,Label number) {
            var card=new BrightnessCard {Size=new Size(260,126),Dock=DockStyle.Fill};
            var icon=new Label {Text=glyph,Font=new Font("Segoe UI Symbol",13),Bounds=new Rectangle(12,10,24,26),Tag="muted"};
            var title=new Label {Text=label,Font=new Font("Segoe UI Semibold",11),Location=new Point(40,12),AutoSize=true};
            number.SetBounds(12,42,220,40); number.Font=new Font("Segoe UI Semibold",21);
            slider.SetBounds(8,86,244,30); slider.Minimum=0; slider.Maximum=100; slider.TickStyle=TickStyle.None; slider.LargeChange=10;
            slider.AccessibleName=label+" SDR brightness";
            slider.Anchor=number.Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right;
            card.Controls.AddRange(new Control[]{icon,title,number,slider}); return card;
        }
        public void LoadSettings(uint day,uint night,string mode,int dayStart,int nightStart,bool enforce) {
            initializing=true; DayLevel=day; NightLevel=night;
            DaySlider.Value=LevelPercent(day);
            NightSlider.Value=LevelPercent(night);
            Switching.SelectedIndex=mode=="Schedule"?1:mode=="NightLight"?2:mode=="SunriseSunset"?3:0;
            DayStart.Value=validDayStart=DateTime.Today.AddMinutes(dayStart);
            NightStart.Value=validNightStart=DateTime.Today.AddMinutes(nightStart);
            Enforce.Checked=enforce; initializing=false; UpdateValue(); RefreshControls();
        }
        static int LevelPercent(uint level) { return (int)Math.Max(0,Math.Min(100,((long)level-1000+25)/50)); }
        void UpdateValue() {
            bool manual=Switching.ValueIndex==0 && CanAdjust;
            readoutTitle.Text=!CanAdjust && readoutLevel!=0 ? "Last used brightness" : manual?"Manual brightness":"Current brightness";
            value.Text=manual ? Slider.Value+"%" : readoutLevel==0?"\u2014":LevelPercent(readoutLevel)+"%";
            value.AccessibleName=readoutTitle.Text+" "+(value.Text=="\u2014"?"unavailable":value.Text);
            dayValue.Text=DayLevel==0?"--":DaySlider.Value+"%"; nightValue.Text=NightLevel==0?"--":NightSlider.Value+"%";
        }
        public void SetReadoutLevel(uint level) { readoutLevel=level; UpdateValue(); }
        public void InitializeLevel(uint level) {
            if (SelectedLevel!=0 && (CanAdjust || LevelEdited)) return;
            initializing=true; SelectedLevel=level;
            Slider.Value=LevelPercent(level);
            if(DayLevel==0) { DayLevel=level; DaySlider.Value=Slider.Value; }
            if(NightLevel==0) { NightLevel=level; NightSlider.Value=Slider.Value; }
            initializing=false; UpdateValue();
        }
        public void RefreshAvailability(bool available, bool busy, string message, bool saving=false, bool hdrOff=false) {
            CanAdjust=available; this.busy=busy; this.hdrOff=hdrOff;
            // Move the thumb for display only. A history refresh must never queue an edit.
            initializing=true;
            Slider.Value=LevelPercent(hdrOff ? readoutLevel : SelectedLevel);
            initializing=false;
            Restore.Enabled=!String.IsNullOrEmpty(PreferenceKey) && SelectedLevel>=1000 && SelectedLevel<=6000 && !busy;
            availabilityMessage=message;
            SaveStatus.SetIdleText(validationMessage ?? availabilityMessage);
            if(busy && saving && !savingDisplay && validationMessage==null) SaveStatus.BeginSaving();
            if(savingDisplay && !saving) SaveStatus.ClearUnconfirmed();
            savingDisplay=busy && saving;
            RefreshControls(); UpdateValue();
        }
        internal void ShowSaved() {
            LevelEdited=false;
            SaveStatus.Confirm(String.IsNullOrEmpty(PreferenceKey)?"\u2713 Applied":DialogTheme.SavedText);
        }
        void RefreshControls() {
            bool known=SelectedLevel>=1000 && SelectedLevel<=6000;
            bool scheduled=Switching.ValueIndex>0;
            NightLightSettings.Visible=SwitchingMode=="NightLight";
            sliderCard.Visible=hdrOff || (!scheduled && CanAdjust);
            periods.Visible=scheduled && known;
            // Reserve the automatic mode's rows so switching modes doesn't move the controls below.
            int periodsHeight=known ? periods.Height+periods.Margin.Vertical : 0;
            int trackHeight=sliderCard.Height+sliderCard.Margin.Vertical;
            sliderRows.MinimumSize=new Size(0,hdrOff ? trackHeight+periodsHeight : CanAdjust ? periodsHeight : 0);
            Slider.Enabled=CanAdjust && !busy && !scheduled;
            DaySlider.Enabled=NightSlider.Enabled=known && !busy && scheduled;
            Switching.Enabled=known && !busy && !String.IsNullOrEmpty(PreferenceKey);
            DayStart.Enabled=NightStart.Enabled=scheduled && !busy;
            Enforce.Enabled=known && !busy && !String.IsNullOrEmpty(PreferenceKey);
            bool location=SwitchingMode=="SunriseSunset";
            dayLabel.Text=location?"Fallback day starts":"Day starts";
            nightLabel.Text=location?"Fallback night starts":"Night starts";
            LocationStatus.Visible=RefreshLocation.Visible=LocationSettings.Visible=location;
            RefreshLocation.Enabled=LocationSettings.Enabled=!busy;
            if(switchingCard!=null && location!=locationExpanded) {
                int shift=(int)Math.Round(88*DayStart.Height/46.0)*(location?1:-1);
                switchingCard.Height+=shift; locationExpanded=location;
            }
            scheduleHint.Text=location?"Day at sunrise, night at sunset. These 24-hour times are the fallback.":SwitchingMode=="NightLight"?"24-hour local time. Used if Night Light cannot be read.":scheduled?"24-hour local time. Select hours or minutes; use + / - or arrow keys.":"Use the manual brightness slider to adjust the level.";
            if(location && !initializing && Visible) RefreshLocationStatus();
        }
        public void RefreshLocationStatus() {
            BrightnessLocation.Request(false);
            var fix=BrightnessLocation.Current;
            if(fix==null) { LocationStatus.Text=BrightnessLocation.Status+" Using fallback times."; return; }
            var zone=TimeZoneInfo.Local;
            string key=DateTime.Today.Ticks+"|"+fix.CapturedUtc.Ticks+"|"+zone.ToSerializedString();
            if(key!=solarKey) {
                var rise=BrightnessSun.Crossing(DateTime.Today,fix.Latitude,fix.Longitude,zone,true);
                var set=BrightnessSun.Crossing(DateTime.Today,fix.Latitude,fix.Longitude,zone,false);
                solarSummary="Today: sunrise "+(rise.HasValue?rise.Value.ToString("HH:mm"):"none")+"  /  sunset "+(set.HasValue?set.Value.ToString("HH:mm"):"none")+" (local time)";
                solarKey=key;
            }
            LocationStatus.Text=solarSummary+"\nWindows location; calculated on this PC.";
        }
    }
    public sealed class CommunityListDownload {
        public string Result { get; private set; }
        public string Error { get; private set; }
        public volatile bool Finished;
        public void Start() {
            System.Threading.ThreadPool.QueueUserWorkItem(delegate {
                try {
                    System.Net.ServicePointManager.SecurityProtocol |= System.Net.SecurityProtocolType.Tls12;
                    var request = (System.Net.HttpWebRequest)System.Net.WebRequest.Create("https://raw.githubusercontent.com/notuxius/hdr-control/main/HdrApps.community.txt");
                    request.UserAgent = "HdrContextMenu";
                    request.Accept = "text/plain";
                    request.CachePolicy = new System.Net.Cache.RequestCachePolicy(System.Net.Cache.RequestCacheLevel.NoCacheNoStore);
                    request.Timeout = 10000;
                    request.ReadWriteTimeout = 10000;
                    // Bound both total download time and bytes, including chunked responses.
                    using (var deadline = new System.Threading.Timer(delegate { request.Abort(); }, null, 20000, System.Threading.Timeout.Infinite))
                    using (var response = request.GetResponse()) {
                        const int limit = 1024 * 1024;
                        if (response.ContentLength > limit) throw new System.IO.InvalidDataException("Community list is too large.");
                        using (var stream = response.GetResponseStream())
                        using (var data = new System.IO.MemoryStream()) {
                            var buffer = new byte[8192];
                            int read;
                            while ((read = stream.Read(buffer, 0, buffer.Length)) > 0) {
                                if (data.Length + read > limit) throw new System.IO.InvalidDataException("Community list is too large.");
                                data.Write(buffer, 0, read);
                            }
                            Result = new System.Text.UTF8Encoding(false, true).GetString(data.ToArray()).TrimStart('\uFEFF');
                        }
                    }
                } catch (System.Net.WebException ex) {
                    if (ex.Response != null) ex.Response.Close();
                    Error = ex.Message;
                } catch (Exception ex) { Error = ex.Message; }
                finally { Finished = true; }
            });
        }
    }
    public sealed class UpdateCheck {
        public string Result { get; private set; }
        public string Error { get; private set; }
        public bool NoRelease { get; private set; }
        public volatile bool Finished;
        public void Start() {
            System.Threading.ThreadPool.QueueUserWorkItem(delegate {
                try {
                    System.Net.ServicePointManager.SecurityProtocol |= System.Net.SecurityProtocolType.Tls12;
                    var request = (System.Net.HttpWebRequest)System.Net.WebRequest.Create("https://api.github.com/repos/notuxius/hdr-control/releases/latest");
                    request.UserAgent = "HdrContextMenu";
                    request.Accept = "application/vnd.github+json";
                    request.Timeout = 10000;
                    request.ReadWriteTimeout = 10000;
                    using (var response = request.GetResponse())
                    using (var reader = new System.IO.StreamReader(response.GetResponseStream())) Result = reader.ReadToEnd();
                } catch (System.Net.WebException ex) {
                    using (var response = ex.Response as System.Net.HttpWebResponse) {
                        if (response != null && response.StatusCode == System.Net.HttpStatusCode.NotFound) NoRelease = true;
                        else Error = ex.Message;
                    }
                } catch (Exception ex) { Error = ex.Message; }
                finally { Finished = true; }
            });
        }
    }
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
        static readonly MethodInfo UpdateIconMethod = typeof(NotifyIcon).GetMethod("UpdateIcon", BindingFlags.Instance | BindingFlags.NonPublic);
        public static void Refresh(NotifyIcon icon) {
            // The Icon setter ignores identical instances. .NET Framework's
            // update path republishes the current image without removing the
            // tray entry, changing its position, or allocating another HICON.
            if (icon != null && icon.Visible && UpdateIconMethod != null)
                UpdateIconMethod.Invoke(icon, new object[] { true });
        }
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
    public sealed class TrayPressTracker : IDisposable {
        [StructLayout(LayoutKind.Sequential)]
        struct RawDevice { public ushort Page,Usage; public uint Flags; public IntPtr Target; }
        [StructLayout(LayoutKind.Sequential)]
        struct NativeMessage { public IntPtr Window; public uint Message; public UIntPtr WParam; public IntPtr LParam; public uint Time; public Point Point; public uint Private; }
        [DllImport("user32.dll", SetLastError=true)]
        static extern bool RegisterRawInputDevices(RawDevice[] devices,uint count,uint size);
        [DllImport("user32.dll")] static extern uint GetRawInputData(IntPtr input,uint command,IntPtr data,ref uint size,uint headerSize);
        [DllImport("user32.dll")] static extern int GetMessagePos();
        [DllImport("user32.dll")] static extern int GetMessageTime();
        [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
        [DllImport("user32.dll")] static extern bool PeekMessage(out NativeMessage message,IntPtr window,uint min,uint max,uint remove);
        [DllImport("user32.dll")] static extern int GetMessage(out NativeMessage message,IntPtr window,uint min,uint max);
        [DllImport("user32.dll")] static extern bool TranslateMessage(ref NativeMessage message);
        [DllImport("user32.dll")] static extern IntPtr DispatchMessage(ref NativeMessage message);
        [DllImport("user32.dll")] static extern bool PostThreadMessage(uint thread,uint message,UIntPtr wParam,IntPtr lParam);
        sealed class PressState {
            public readonly Rectangle Anchor;
            public readonly int VisibleMenu;
            public readonly int DismissedMenu,DismissedAt;
            public PressState(Rectangle anchor,int visibleMenu,int dismissedMenu,int dismissedAt) { Anchor=anchor; VisibleMenu=visibleMenu; DismissedMenu=dismissedMenu; DismissedAt=dismissedAt; }
        }
        sealed class InputWindow : NativeWindow, IDisposable {
            readonly TrayPressTracker owner;
            readonly IntPtr buffer=Marshal.AllocHGlobal(64);
            public InputWindow(TrayPressTracker owner) {
                this.owner=owner;
                CreateHandle(new CreateParams {Caption="HDR mouse notifications",Parent=new IntPtr(-3)});
            }
            protected override void WndProc(ref Message m) {
                if(m.Msg==0x00ff) {
                    uint size=64,header=(uint)(8+2*IntPtr.Size);
                    uint read=GetRawInputData(m.LParam,0x10000003,buffer,ref size,header);
                    if(read!=UInt32.MaxValue && read>=header+24 && Marshal.ReadInt32(buffer)==0) {
                        int buttons=(ushort)Marshal.ReadInt16(buffer,(int)header+4);
                        if((buttons&0x15)!=0) { // Left, right, or middle button down; never keyboard input.
                            int position=GetMessagePos();
                            owner.CapturePressAt(new Point((short)position,(short)(position>>16)),GetMessageTime());
                        }
                    }
                }
                base.WndProc(ref m);
            }
            public void Dispose() { DestroyHandle(); Marshal.FreeHGlobal(buffer); }
        }
        readonly NotifyIcon icon;
        readonly ContextMenuStrip controls, settings;
        volatile bool listening;
        readonly Thread inputThread;
        uint inputThreadId;
        volatile PressState state;
        Exception startupError;
        bool disposed;
        Rectangle anchor;
        int menuAtPress;
        public bool IsListening { get { return listening; } }
        public TrayPressTracker(NotifyIcon icon, ContextMenuStrip controls, ContextMenuStrip settings) {
            this.icon=icon; this.controls=controls; this.settings=settings;
            PublishState(null,EventArgs.Empty);
            // Raw input is asynchronous. Unlike a managed WH_MOUSE_LL callback,
            // CLR pauses and process enumeration cannot stall the system cursor.
            using(var ready=new ManualResetEvent(false)) {
                inputThread=new Thread(delegate() { Listen(ready); });
                inputThread.IsBackground=true; inputThread.Name="HDR tray input observer";
                inputThread.SetApartmentState(ApartmentState.STA);
                inputThread.Start(); ready.WaitOne();
            }
            if(startupError!=null) throw new InvalidOperationException("Could not start tray mouse observer.",startupError);
            controls.VisibleChanged+=PublishState; settings.VisibleChanged+=PublishState;
        }
        void Listen(ManualResetEvent ready) {
            InputWindow window=null;
            try {
                NativeMessage message;
                PeekMessage(out message,IntPtr.Zero,0,0,0); // Create the thread message queue before shutdown can be posted.
                inputThreadId=GetCurrentThreadId();
                window=new InputWindow(this);
                listening=RegisterRawInputDevices(new[]{new RawDevice {Page=1,Usage=2,Flags=0x100 /* INPUTSINK */,Target=window.Handle}},1,(uint)Marshal.SizeOf(typeof(RawDevice)));
                if(!listening) throw new System.ComponentModel.Win32Exception(Marshal.GetLastWin32Error());
            } catch(Exception error) { startupError=error; }
            finally { ready.Set(); }
            try {
                if(!listening) return;
                NativeMessage message;
                while(GetMessage(out message,IntPtr.Zero,0,0)>0) { TranslateMessage(ref message); DispatchMessage(ref message); }
            } finally {
                if(listening) RegisterRawInputDevices(new[]{new RawDevice {Page=1,Usage=2,Flags=1 /* REMOVE */}},1,(uint)Marshal.SizeOf(typeof(RawDevice)));
                listening=false;
                if(window!=null) window.Dispose();
            }
        }
        void PublishState(object sender,EventArgs e) {
            int visible=controls.Visible ? 1 : settings.Visible ? 2 : 0;
            PressState previous=state;
            int dismissed=previous==null?0:previous.DismissedMenu,when=previous==null?0:previous.DismissedAt;
            if(visible==0 && previous!=null && previous.VisibleMenu!=0) { dismissed=previous.VisibleMenu; when=Environment.TickCount; }
            state=new PressState(anchor,visible,dismissed,when);
        }
        public void RefreshAnchor() { TrayIconPosition.TryGetBounds(icon, out anchor); PublishState(null,EventArgs.Empty); }
        public void CapturePress(Point point) {
            PressState current=state;
            Interlocked.Exchange(ref menuAtPress,current.Anchor.Contains(point) ? current.VisibleMenu : 0);
        }
        internal void CapturePressAt(Point point,int timestamp) {
            PressState current=state;
            int visible=current.VisibleMenu;
            // The queued notification may arrive just after Explorer dismisses
            // the menu. Recover the state at the original input timestamp.
            int age=unchecked(current.DismissedAt-timestamp);
            if(visible==0 && age>=0 && age<=250) visible=current.DismissedMenu;
            Interlocked.Exchange(ref menuAtPress,current.Anchor.Contains(point)?visible:0);
        }
        public bool ConsumeHide(ContextMenuStrip requested) {
            int pressed=Interlocked.Exchange(ref menuAtPress,0);
            return requested.Visible || pressed==(requested==controls ? 1 : 2);
        }
        public void Dispose() {
            if(disposed) return;
            disposed=true;
            controls.VisibleChanged-=PublishState; settings.VisibleChanged-=PublishState;
            PostThreadMessage(inputThreadId,0x0012 /* WM_QUIT */,UIntPtr.Zero,IntPtr.Zero);
            inputThread.Join(1000);
            Interlocked.Exchange(ref menuAtPress,0);
        }
    }
    public sealed class TrayPopupMenu : ContextMenuStrip {
        [DllImport("dwmapi.dll")]
        static extern int DwmSetWindowAttribute(IntPtr window, int attribute, ref int value, int size);
        [DllImport("user32.dll")]
        static extern bool SetWindowPos(IntPtr window, IntPtr after, int x, int y, int width, int height, uint flags);
        Padding surfacePadding = new Padding(6);
        Point popupAnchor;
        public NotifyIcon AnchorIcon { get; set; }
        public bool ShowActionIcons { get; set; }
        public bool TransitionsDisabled { get; private set; }
        protected override void OnHandleCreated(EventArgs e) {
            base.OnHandleCreated(e);
            // These popups are repositioned and reparented by WinForms. DWM's
            // transition can briefly animate that intermediate geometry on
            // close. Disable transitions only for our popup windows.
            int disabled = 1;
            TransitionsDisabled = DwmSetWindowAttribute(Handle, 3 /* DWMWA_TRANSITIONS_FORCEDISABLED */, ref disabled, sizeof(int)) == 0;
        }
        protected override Padding DefaultPadding { get { return surfacePadding; } }
        public void SetSurfacePadding(Padding value) { surfacePadding = value; Padding = value; }
        protected override void OnClosing(ToolStripDropDownClosingEventArgs e) {
            base.OnClosing(e);
            // Hide the native surface before WinForms resets/reparents it, so
            // no intermediate collapsed frame is presented during teardown.
            if (!e.Cancel && IsHandleCreated)
                SetWindowPos(Handle, IntPtr.Zero, 0,0,0,0, 0x97 /* HIDEWINDOW|NOACTIVATE|NOZORDER|NOMOVE|NOSIZE */);
        }
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
        public string AutomationDecision { get; private set; }

        public void SetCombinedStatus(string hdr, string decision) {
            Tag = hdr;
            if (hdr == "HDR: Unavailable" || hdr == "HDR: Temporarily unreadable") {
                AutomationDecision = null;
                Text = hdr;
                return;
            }
            AutomationDecision = decision;
            string detail = decision;
            switch (decision) {
                case null: case "": detail = "Unknown"; break;
                case "Automatic HDR is paused": detail = "Paused"; break;
                case "Automatic HDR: idle": detail = "Idle"; break;
                case "Automation waiting: app list or process scan failed": detail = "App list or process scan failed"; break;
            }
            string label = hdr + " \u00b7 Auto: " + detail;
            Text = label.Length > 85 ? label.Substring(0, 82) + "..." : label;
        }
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
        // One 16-DIP slot and stroke weight for every menu symbol.
        const float GlyphSize = 16f;
        const float GlyphStroke = 1.5f;
        static void DrawGlyph(Graphics g, ToolStripItem item, int left, Color color) {
            var statusItem = item as TrayStatusItem;
            string decision = statusItem == null ? null : statusItem.AutomationDecision;
            string status = item.Tag as string ?? item.Text;
            bool autoPreference = item.Name == "AutoHdrPreference";
            if (item.Name == "HdrAction") status = status == "On" || status == "Enable HDR" ? "HDR: Enabled" : "HDR: Disabled";
            else if (autoPreference) status = ((ToolStripMenuItem)item).Checked ? "HDR: Disabled" : "HDR: Enabled";
            if (!Contrast && (item.Name == "Startup" || item.Name == "Preference") && ((ToolStripMenuItem)item).Checked) color = Color.FromArgb(68,195,149);
            bool highlighted = item.Enabled && item.Selected;
            Color background = Contrast ? (highlighted ? SystemColors.Highlight : SystemColors.Menu) : (highlighted ? Hover : Surface);
            if (!Contrast && (item.Name == "HdrStatus" || ((item.Name == "HdrAction" || autoPreference) && item.Enabled))) {
                if (status == "HDR: Disabled") color = Color.FromArgb(227, 190, 44);
                else if (status == "HDR: Enabled") color = Color.FromArgb(68, 195, 149);
                else if (status == "HDR: Unavailable") color = Color.FromArgb(235, 126, 126);
            }
            var saved = g.Save();
            try {
                float scale = g.DpiX / 96f;
                g.TranslateTransform(left, (float)Math.Round((item.Height - GlyphSize * scale) / 2f));
                g.ScaleTransform(scale, scale);
                g.SmoothingMode = SmoothingMode.AntiAlias;
                using (var pen = new Pen(color, GlyphStroke))
                using (var path = new GraphicsPath()) {
                    pen.StartCap = pen.EndCap = LineCap.Round;
                    pen.LineJoin = LineJoin.Round;
                    if (item.Name == "DisplaySettings" || item.Name == "Displays") {
                        path.AddRectangle(new RectangleF(1.5f,2.5f,13,9));
                        AddStroke(path,8,11.5f,8,14.5f);
                        AddStroke(path,5.5f,14.5f,10.5f,14.5f);
                        g.DrawPath(pen,path);
                        path.Reset();
                        if (item.Name == "DisplaySettings") DrawSettingsGear(g, pen, background);
                    } else if (item.Name == "SdrBrightness") {
                        path.AddEllipse(4.5f,4.5f,7,7);
                        for (int i=0;i<8;i++) {
                            double angle=i*Math.PI/4;
                            AddStroke(path,8+(float)Math.Cos(angle)*5.5f,8+(float)Math.Sin(angle)*5.5f,
                                8+(float)Math.Cos(angle)*7,8+(float)Math.Sin(angle)*7);
                        }
                    } else if (item.Name == "RefreshDisplays") {
                        AddRefreshSymbol(path);
                    } else if (item.Name == "CheckUpdates") {
                        AddStroke(path,8,1.5f,8,10.5f);
                        path.StartFigure();
                        path.AddLines(new PointF[] {new PointF(4.5f,7),new PointF(8,10.5f),new PointF(11.5f,7)});
                        path.StartFigure();
                        path.AddLines(new PointF[] {new PointF(1.5f,11),new PointF(1.5f,14.5f),new PointF(14.5f,14.5f),new PointF(14.5f,11)});
                    } else if (item.Name == "About") {
                        path.AddEllipse(1,1,14,14);
                        AddStroke(path,8,7.5f,8,11.5f);
                        using (var brush = new SolidBrush(color)) g.FillEllipse(brush,7.25f,4,1.5f,1.5f);
                    } else if (item.Name == "GameLists") {
                        path.AddBezier(4,4,2,4,1,8,1,11);
                        path.AddBezier(1,11,1,14,3,14,5,10);
                        path.AddLine(5,10,11,10);
                        path.AddBezier(11,10,13,14,15,14,15,11);
                        path.AddBezier(15,11,15,8,14,4,12,4);
                        path.CloseFigure();
                        AddStroke(path,3,7,6,7);
                        AddStroke(path,4.5f,5.5f,4.5f,8.5f);
                        using (var brush = new SolidBrush(color)) {
                            g.FillEllipse(brush,10,6.5f,1.5f,1.5f);
                            g.FillEllipse(brush,12,5.5f,1.5f,1.5f);
                        }
                    } else if (item.Name == "AppSettings") {
                        AddStroke(path,1.5f,4,4,4);
                        AddStroke(path,8,4,14.5f,4);
                        path.AddEllipse(4,2,4,4);
                        AddStroke(path,1.5f,12,8,12);
                        AddStroke(path,12,12,14.5f,12);
                        path.AddEllipse(8,10,4,4);
                    } else if (item.Name == "AppList") {
                        path.AddRectangle(new RectangleF(2,1,12,14));
                        AddStroke(path,5,5,11,5);
                        AddStroke(path,5,8,11,8);
                        AddStroke(path,5,11,9,11);
                    } else if (item.Name == "Startup") {
                        path.AddBezier(2,2.5f,6,-1,10,5,14,2);
                        path.AddLine(14,2,14,10);
                        path.AddBezier(14,10,10,13,6,7,2,10.5f);
                        path.CloseFigure();
                        if (((ToolStripMenuItem)item).Checked) {
                            using (var brush = new SolidBrush(color)) g.FillPath(brush,path);
                        }
                        AddStroke(path,2,10.5f,2,15);
                    } else if (item.Name == "Preference") {
                        path.AddEllipse(1,1,14,14);
                        if (((ToolStripMenuItem)item).Checked) AddCheck(path);
                    } else if (item.Name == "ExitAction") {
                        path.AddArc(1,1,14,14,-45,270);
                        AddStroke(path,8,1,8,7.5f);
                    } else if (item.Name == "HdrStatus") {
                        bool play = decision == "Automatic HDR: idle" ||
                            (decision != null && decision.StartsWith("Enabled for ", StringComparison.Ordinal));
                        bool showSymbol = play || decision == "Automatic HDR is paused";
                        // Match the action circle's outer edge, including its stroke.
                        float edge = 1f - GlyphStroke / 2f;
                        float diameter = 14f + GlyphStroke;
                        if (status == "HDR: Mixed") {
                            // Clip the same ellipse at its center so neither color paints over the other.
                            var pixelOffset = g.PixelOffsetMode;
                            for (int half = 0; half < 2; half++) {
                                var fill = half == 0 ? (Contrast ? color : Color.FromArgb(68,195,149))
                                                     : (Contrast ? background : Color.FromArgb(227,190,44));
                                var mixedState = g.Save();
                                g.PixelOffsetMode = PixelOffsetMode.Half;
                                g.SetClip(new RectangleF(half * GlyphSize / 2,0,GlyphSize / 2,GlyphSize), CombineMode.Intersect);
                                using (var brush = new SolidBrush(fill)) g.FillEllipse(brush,edge,edge,diameter,diameter);
                                g.PixelOffsetMode = pixelOffset;
                                if (showSymbol) DrawPlayPause(g, scale, Contrast && half == 1 ? color : background, play);
                                g.Restore(mixedState);
                            }
                        } else {
                            using (var brush = new SolidBrush(color)) g.FillEllipse(brush,edge,edge,diameter,diameter);
                            if (showSymbol) DrawPlayPause(g, scale, background, play);
                            else if (!String.IsNullOrEmpty(decision)) DrawWaitingBadge(g, scale, color, background);
                        }
                    } else if (item.Name == "HdrAction" || autoPreference) {
                        path.AddEllipse(1,1,14,14);
                        if (autoPreference) {
                            DrawPlayPause(g, scale, color, status == "HDR: Enabled");
                        } else if (status == "HDR: Unavailable") {
                            AddStroke(path,5.5f,5.5f,10.5f,10.5f);
                            AddStroke(path,10.5f,5.5f,5.5f,10.5f);
                        } else if (status == "HDR: Enabled") {
                            AddCheck(path);
                        } else if (status == "HDR: Mixed") {
                            using (var brush = new SolidBrush(color)) g.FillPie(brush,4.5f,4.5f,7,7,-90,180);
                        } else { AddStroke(path,5,8,11,8); }
                    }
                    // A single path keeps shared endpoints and crossings equally weighted.
                    if (path.PointCount > 0) g.DrawPath(pen,path);
                }
            } finally { g.Restore(saved); }
        }
        static void DrawPlayPause(Graphics g, float scale, Color color, bool play) {
            using (var brush = new SolidBrush(color)) {
                if (play) {
                    g.FillPolygon(brush,new PointF[] {
                        new PointF(5.5f,4),new PointF(12,8),new PointF(5.5f,12)
                    });
                } else {
                    // Mirror the lit pixels about the circle's center pixel.
                    float center = (float)Math.Round(GlyphSize * scale / 2);
                    int width = Px(g,1);
                    int offset = (int)Math.Round(2 * scale - (width - 1) / 2f);
                    int halfHeight = (int)Math.Round((7 * scale - 1) / 2);
                    float top = (center - halfHeight) / scale;
                    float height = (2 * halfHeight + 1) / scale;
                    g.SmoothingMode = SmoothingMode.None;
                    g.FillRectangle(brush,(center-offset-width+1)/scale,top,width/scale,height);
                    g.FillRectangle(brush,(center+offset)/scale,top,width/scale,height);
                    g.SmoothingMode = SmoothingMode.AntiAlias;
                }
            }
        }
        static void AddRefreshSymbol(GraphicsPath path) {
            // Share the exact two-arrow design between Refresh displays and badges.
            path.AddArc(1.5f,1.5f,13,13,190,145);
            path.AddLine(13.89f,5.25f,10.6f,5.25f);
            AddStroke(path,13.89f,5.25f,13.89f,1.96f);
            path.StartFigure();
            path.AddArc(1.5f,1.5f,13,13,10,145);
            path.AddLine(2.11f,10.75f,5.4f,10.75f);
            AddStroke(path,2.11f,10.75f,2.11f,14.04f);
        }
        static void DrawWaitingBadge(Graphics g, float scale, Color face, Color ink) {
            // Match the badge position in the native tray ICO frames.
            float gap = (float)Math.Round(2 * scale);
            float height = (float)Math.Round(4 * scale);
            float cx = ((float)Math.Round(11.25f * scale - gap / 2) + gap / 2) / scale;
            float cy = ((float)Math.Round(11.25f * scale - height / 2) + height / 2) / scale;
            g.SetClip(new RectangleF(0,0,GlyphSize,GlyphSize), CombineMode.Intersect);
            g.TranslateTransform(cx, cy);
            g.PixelOffsetMode = PixelOffsetMode.Half;
            using (var outline = new SolidBrush(ink))
            using (var fill = new SolidBrush(face)) {
                g.FillEllipse(outline,-4.8f,-4.8f,9.6f,9.6f);
                g.FillEllipse(fill,-4.25f,-4.25f,8.5f,8.5f);
                g.ScaleTransform(.4f,.4f);
                g.TranslateTransform(-GlyphSize/2,-GlyphSize/2);
                using (var path = new GraphicsPath())
                using (var pen = new Pen(ink,2.2f)) {
                    pen.StartCap = pen.EndCap = LineCap.Round;
                    pen.LineJoin = LineJoin.Round;
                    AddRefreshSymbol(path);
                    g.DrawPath(pen,path);
                }
            }
        }
        static void AddStroke(GraphicsPath path, float x1, float y1, float x2, float y2) {
            path.StartFigure();
            path.AddLine(x1,y1,x2,y2);
        }
        static void AddCheck(GraphicsPath path) {
            path.StartFigure();
            path.AddLines(new PointF[] {new PointF(4.5f,8),new PointF(7,10.5f),new PointF(11.5f,5.5f)});
        }
        static void DrawSettingsGear(Graphics g, Pen pen, Color background) {
            var gear = new PointF[24];
            for (int i = 0; i < gear.Length; i++) {
                double angle = i * Math.PI / 12;
                float radius = i % 4 == 1 || i % 4 == 2 ? 3f : 2.2f;
                gear[i] = new PointF(12.1f + radius * (float)Math.Cos(angle), 12.1f + radius * (float)Math.Sin(angle));
            }
            using (var backdrop = new SolidBrush(background)) g.FillEllipse(backdrop,8.1f,8.1f,8,8);
            using (var path = new GraphicsPath()) {
                path.AddPolygon(gear);
                g.DrawPath(pen,path);
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
            using (var pen = new Pen(color, GlyphStroke * e.Graphics.DpiX / 96f)) {
                pen.StartCap = pen.EndCap = LineCap.Round;
                pen.LineJoin = LineJoin.Round;
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
