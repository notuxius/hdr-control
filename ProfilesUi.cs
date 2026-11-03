using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

namespace LocalHdrMenu {
    public sealed class DisplayChoice {
        public string Key, Label;
        public DisplayChoice(string key,string label) { Key=key; Label=label; }
        public override string ToString() { return Label; }
    }
    public sealed class HdrEventWindow : Form {
        [DllImport("user32.dll",SetLastError=true)] static extern bool RegisterHotKey(IntPtr window,int id,uint modifiers,uint key);
        [DllImport("user32.dll")] static extern bool UnregisterHotKey(IntPtr window,int id);
        readonly List<int> ids=new List<int>();
        public event EventHandler DisplayChanged;
        public event EventHandler HotkeyPressed;
        public int LastHotkey;
        public HdrEventWindow() { ShowInTaskbar=false; var handle=Handle; }
        public bool Bind(int id,uint modifiers,uint key) {
            if (!RegisterHotKey(Handle,id,modifiers|0x4000,key)) return false;
            ids.Add(id); return true;
        }
        public void ClearHotkeys() { foreach(int id in ids) UnregisterHotKey(Handle,id); ids.Clear(); }
        protected override void WndProc(ref Message m) {
            if (m.Msg==0x007e || (m.Msg==0x0218 && (m.WParam.ToInt32()==7 || m.WParam.ToInt32()==18))) {
                if (DisplayChanged!=null) DisplayChanged(this,EventArgs.Empty);
            }
            if (m.Msg==0x0312) { LastHotkey=m.WParam.ToInt32(); if (HotkeyPressed!=null) HotkeyPressed(this,EventArgs.Empty); }
            base.WndProc(ref m);
        }
        protected override void Dispose(bool disposing) { if(disposing) ClearHotkeys(); base.Dispose(disposing); }
    }
    public static class ProfileUi {
        public static void Initialize(Form form,string title,int width,int height,bool fixedSize=false) {
            form.Text=title; form.Font=new Font("Segoe UI",10);
            form.AutoScaleDimensions=new SizeF(96,96); form.AutoScaleMode=AutoScaleMode.Dpi;
            if(fixedSize) { form.FormBorderStyle=FormBorderStyle.FixedDialog; form.MaximizeBox=false; }
            form.ClientSize=new Size(width,height);
            if(!fixedSize) form.MinimumSize=new Size(width+16,height+39);
            form.StartPosition=FormStartPosition.CenterScreen;
        }
        public static void AddHeader(Form form,string title,string caption) {
            form.SuspendLayout();
            var anchors=new Dictionary<Control,AnchorStyles>();
            foreach(Control child in form.Controls) { anchors[child]=child.Anchor; child.Anchor=AnchorStyles.Top|AnchorStyles.Left; child.Top+=96; }
            form.ClientSize=new Size(form.ClientSize.Width,form.ClientSize.Height+96);
            form.MinimumSize=new Size(form.MinimumSize.Width,form.MinimumSize.Height+96);
            foreach(var pair in anchors) pair.Key.Anchor=pair.Value;
            form.Controls.Add(DialogTheme.Heading(title,16,16,form.ClientSize.Width-32));
            form.Controls.Add(DialogTheme.Caption(caption,16,59,form.ClientSize.Width-32,28));
            form.ResumeLayout(false);
        }
        public static void Theme(Control control) { DialogTheme.Apply(control); }
        public static Label Label(string text,int x,int y,int width=190) { return new Label {Text=text,Bounds=new Rectangle(x,y,width,26)}; }
        public static Button Button(string text,int x,int y,int width=105) { return new DialogButton {Text=text,Bounds=new Rectangle(x,y,width,36),Primary=text=="Save" || text=="Apply" || text=="Choose"}; }
        public static DataGridView Grid(int x,int y,int width,int height) {
            return new DataGridView {Bounds=new Rectangle(x,y,width,height),Anchor=AnchorStyles.Top|AnchorStyles.Bottom|AnchorStyles.Left|AnchorStyles.Right,
                AllowUserToAddRows=false,AllowUserToDeleteRows=false,RowHeadersVisible=false,AutoSizeColumnsMode=DataGridViewAutoSizeColumnsMode.Fill,
                SelectionMode=DataGridViewSelectionMode.FullRowSelect,MultiSelect=false};
        }
    }
    public sealed class GameRuleForm : DialogForm {
        public readonly DialogTextInput Executable=new DialogTextInput(), ExactPath=new DialogTextInput(), LaunchPath=new DialogTextInput(), Arguments=new DialogTextInput(), WorkingDirectory=new DialogTextInput();
        public readonly CheckBox RuleEnabled=new DialogCheckBox();
        public readonly DialogNumberInput StartDelay=new DialogNumberInput(), ExitDelay=new DialogNumberInput();
        public readonly ComboBox ExitPolicy=new DialogComboBox();
        public readonly CheckedListBox Targets=new DialogCheckedListBox();
        public readonly Button SaveButton;
        public GameRuleForm() {
            ProfileUi.Initialize(this,"Game HDR settings",680,650);
            Controls.Add(ProfileUi.Label("Executable to watch",16,18)); Executable.SetBounds(220,16,440,28);
            RuleEnabled.Text="Enable this game (unchecked excludes it)"; RuleEnabled.SetBounds(220,51,440,28);
            Controls.Add(ProfileUi.Label("Exact path (optional)",16,91)); ExactPath.SetBounds(220,89,440,28);
            Controls.Add(ProfileUi.Label("Monitors",16,130)); Targets.SetBounds(220,128,440,112); Targets.CheckOnClick=true;
            Controls.Add(ProfileUi.Label("No selection means all active HDR monitors.",220,244,440));
            Controls.Add(ProfileUi.Label("Delay before HDR (s)",16,281)); StartDelay.SetBounds(220,275,140,36); StartDelay.Maximum=300;
            Controls.Add(ProfileUi.Label("After exit (s)",380,281,130)); ExitDelay.SetBounds(520,275,140,36); ExitDelay.Minimum=2; ExitDelay.Maximum=300;
            Controls.Add(ProfileUi.Label("When the game exits",16,320)); ExitPolicy.SetBounds(220,318,440,28); ExitPolicy.DropDownStyle=ComboBoxStyle.DropDownList;
            ExitPolicy.Items.AddRange(new object[]{"Use default","Return to SDR","Restore previous state"}); ExitPolicy.SelectedIndex=0;
            Controls.Add(ProfileUi.Label("Launch with HDR",16,366)); LaunchPath.SetBounds(220,364,340,28);
            var browse=ProfileUi.Button("Browse...",568,362,92);
            browse.Click+=delegate { using(var dialog=new OpenFileDialog {Filter="Programs (*.exe)|*.exe",CheckFileExists=true}) {
                if(dialog.ShowDialog(this)==DialogResult.OK) { LaunchPath.Text=dialog.FileName; if(String.IsNullOrWhiteSpace(Executable.Text)) Executable.Text=System.IO.Path.GetFileName(dialog.FileName); }
            }};
            Controls.Add(ProfileUi.Label("Arguments",16,407)); Arguments.SetBounds(220,405,440,28);
            Controls.Add(ProfileUi.Label("Working directory",16,448)); WorkingDirectory.SetBounds(220,446,440,28);
            var note=ProfileUi.Label("Launch with HDR enables and verifies the selected displays before starting this program.\r\nFor launchers, set Executable to watch to the actual game. The handoff timeout is 45 seconds.\r\nExact path is optional; leave it blank for store-independent executable matching.",16,495,644); note.Height=82;
            SaveButton=ProfileUi.Button("Save",440,600,105); SaveButton.DialogResult=DialogResult.OK;
            var cancel=ProfileUi.Button("Cancel",555,600,105); cancel.DialogResult=DialogResult.Cancel;
            AcceptButton=SaveButton; CancelButton=cancel;
            Controls.AddRange(new Control[]{Executable,RuleEnabled,ExactPath,Targets,StartDelay,ExitDelay,ExitPolicy,LaunchPath,browse,Arguments,WorkingDirectory,note,SaveButton,cancel});
            var inputs=new DialogTextInput[]{Executable,ExactPath,StartDelay,ExitDelay,LaunchPath,Arguments,WorkingDirectory};
            string[] names={"Executable to watch","Exact path (optional)","Delay before HDR in seconds","Delay after exit in seconds","Launch executable","Launch arguments","Working directory"};
            for(int i=0;i<inputs.Length;i++) { inputs[i].Height=36; inputs[i].AccessibleName=names[i]; }
            Executable.TabIndex=0; RuleEnabled.TabIndex=1; ExactPath.TabIndex=2; Targets.TabIndex=3;
            StartDelay.TabIndex=4; ExitDelay.TabIndex=5; ExitPolicy.TabIndex=6; LaunchPath.TabIndex=7;
            browse.TabIndex=8; Arguments.TabIndex=9; WorkingDirectory.TabIndex=10; SaveButton.TabIndex=11; cancel.TabIndex=12;
            ProfileUi.AddHeader(this,"Game HDR settings","Choose a game, its displays, and how HDR behaves when it starts and exits.");
            SaveButton.Anchor=cancel.Anchor=AnchorStyles.Bottom|AnchorStyles.Right;
            Load+=delegate { SaveButton.Top=cancel.Top=ClientSize.Height-SaveButton.Height-Font.Height; };
            ProfileUi.Theme(this);
            foreach(var input in inputs) input.ApplyTheme();
        }
        public void AddTarget(string key,string label,bool selected) { Targets.Items.Add(new DisplayChoice(key,label),selected); }
        public string[] SelectedTargets() { var keys=new List<string>(); foreach(DisplayChoice item in Targets.CheckedItems) keys.Add(item.Key); return keys.ToArray(); }
    }
    // Delegate process selection to Windows PowerShell's standard grid window.
    public sealed class RunningAppsPicker : IDisposable {
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
        [DllImport("user32.dll")] static extern bool ShowWindowAsync(IntPtr window,int command);
        readonly string childScript;
        readonly System.Windows.Forms.Timer completionTimer=new System.Windows.Forms.Timer();
        Process child;
        string output="",failure="";
        volatile bool outputClosed,errorClosed;
        bool finished,disposed;
        public event EventHandler Completed;
        public string SelectedExecutable { get; private set; }
        public string SelectedPath { get; private set; }
        public Exception Error { get; private set; }
        public string ThemePath { get; set; }
        public RunningAppsPicker() : this(null) { }
        internal RunningAppsPicker(string testScript) {
            childScript=testScript ?? @"
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.UTF8Encoding]::new($false)
try {
    if($env:HDR_PROCESS_GRID_THEME) {
        try {
            Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
            Add-Type -Path $env:HDR_PROCESS_GRID_THEME -ReferencedAssemblies PresentationFramework,PresentationCore,WindowsBase,System.Xaml
            [LocalHdrMenu.ProcessGridTheme]::Install()
        } catch { } # Fall back to the standard grid if styling is unavailable.
    }
    $session=[Diagnostics.Process]::GetCurrentProcess().SessionId
    $rows=@(Get-Process | ForEach-Object {
        $process=$_
        try {
            if($process.SessionId -eq $session) {
                $name=$process.ProcessName+'.exe'
                $path=try { [string]$process.Path } catch { '' }
                [pscustomobject]@{Executable=$name;Path=$path}
            }
        } catch { } finally { $process.Dispose() }
    } | Sort-Object Executable,Path -Unique)
    $selected=$rows | Out-GridView -Title 'Add running game' -OutputMode Single
    if($null -ne $selected) {
        $selection=$selected.Executable+[char]0+$selected.Path
        [Console]::WriteLine([Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($selection)))
    }
} catch {[Console]::Error.WriteLine($_.Exception.Message); exit 1}
";
            completionTimer.Interval=100;
            completionTimer.Tick+=delegate {
                if(disposed || finished || child==null || !child.HasExited || !outputClosed || !errorClosed) return;
                try {
                    if(child.ExitCode!=0) throw new InvalidOperationException(String.IsNullOrWhiteSpace(failure)?"The running game selector could not start.":failure.Trim());
                    if(!String.IsNullOrWhiteSpace(output)) {
                        string[] selection=Encoding.UTF8.GetString(Convert.FromBase64String(output.Trim())).Split(new[]{'\0'},2);
                        if(selection.Length!=2 || String.IsNullOrWhiteSpace(selection[0])) throw new InvalidOperationException("The game selection was incomplete.");
                        SelectedExecutable=selection[0]; SelectedPath=selection[1];
                    }
                } catch(Exception error) {Error=error;}
                finished=true; completionTimer.Stop();
                if(Completed!=null) Completed(this,EventArgs.Empty);
            };
        }
        public void Start() {
            if(disposed || child!=null) return;
            var start=new ProcessStartInfo {
                FileName=System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),@"WindowsPowerShell\v1.0\powershell.exe"),
                Arguments="-NoLogo -NoProfile -NonInteractive -STA -WindowStyle Hidden -EncodedCommand "+Convert.ToBase64String(Encoding.Unicode.GetBytes(childScript)),
                UseShellExecute=false,CreateNoWindow=true,WindowStyle=ProcessWindowStyle.Hidden,
                RedirectStandardOutput=true,RedirectStandardError=true,StandardOutputEncoding=Encoding.UTF8,StandardErrorEncoding=Encoding.UTF8
            };
            start.EnvironmentVariables["HDR_PROCESS_GRID_THEME"]=ThemePath ?? "";
            child=new Process {StartInfo=start};
            child.OutputDataReceived+=delegate(object sender,DataReceivedEventArgs e) {if(e.Data==null) outputClosed=true; else if(output.Length<131072) output+=e.Data;};
            child.ErrorDataReceived+=delegate(object sender,DataReceivedEventArgs e) {if(e.Data==null) errorClosed=true; else if(failure.Length<4096) failure+=e.Data+Environment.NewLine;};
            child.Start(); child.BeginOutputReadLine(); child.BeginErrorReadLine(); completionTimer.Start();
        }
        public void Activate() {
            if(disposed || child==null || child.HasExited) return;
            child.Refresh(); IntPtr handle=child.MainWindowHandle;
            if(handle!=IntPtr.Zero) {ShowWindowAsync(handle,9);SetForegroundWindow(handle);}
        }
        public void Dispose() {
            if(disposed) return;
            disposed=true; completionTimer.Dispose();
            if(child!=null) {
                try {if(!child.HasExited) child.Kill();} catch(InvalidOperationException) { }
                finally {child.Dispose();child=null;}
            }
        }
    }
    public sealed class PresetForm : DialogForm {
        public readonly DialogTextInput PresetName=new DialogTextInput();
        public readonly DataGridView Displays;
        public PresetForm() {
            ProfileUi.Initialize(this,"Display preset",740,470);
            Controls.Add(ProfileUi.Label("Preset name",16,20)); PresetName.SetBounds(160,16,564,36); PresetName.AccessibleName="Preset name";
            Controls.Add(ProfileUi.Label("Select monitors, HDR states, and optional SDR brightness (0-100%).",16,60,710));
            Displays=ProfileUi.Grid(16,96,708,290);
            Displays.Columns.Add(new DataGridViewCheckBoxColumn {CellTemplate=new DialogCheckBoxCell(),Name="Include",HeaderText="Include",FillWeight=45});
            Displays.Columns.Add(new DataGridViewTextBoxColumn {Name="Monitor",HeaderText="Monitor",ReadOnly=true,FillWeight=150});
            Displays.Columns.Add(new DataGridViewCheckBoxColumn {CellTemplate=new DialogCheckBoxCell(),Name="Enabled",HeaderText="HDR enabled",FillWeight=65});
            Displays.Columns.Add(new DataGridViewTextBoxColumn {Name="Brightness",HeaderText="SDR brightness %",FillWeight=90});
            foreach(DataGridViewColumn column in Displays.Columns) {
                if(column is DataGridViewCheckBoxColumn) AddCheckHeader(column);
            }
            Displays.CurrentCellDirtyStateChanged+=delegate {
                if(Displays.CurrentCell is DataGridViewCheckBoxCell && Displays.IsCurrentCellDirty)
                    Displays.CommitEdit(DataGridViewDataErrorContexts.Commit);
            };
            var save=ProfileUi.Button("Save",504,416); save.DialogResult=DialogResult.OK;
            var cancel=ProfileUi.Button("Cancel",619,416); cancel.DialogResult=DialogResult.Cancel;
            Controls.AddRange(new Control[]{PresetName,Displays,save,cancel}); AcceptButton=save; CancelButton=cancel; ProfileUi.AddHeader(this,"Display preset","Save a display setup you can apply in one step."); ProfileUi.Theme(this);
        }
        void AddCheckHeader(DataGridViewColumn column) {
            string label=column.HeaderText;
            Func<int> countChecked=delegate {
                int count=0;
                foreach(DataGridViewRow row in Displays.Rows)
                    if(true.Equals(row.Cells[column.Index].Value)) count++;
                return count;
            };
            Action update=delegate {
                int count=countChecked();
                column.HeaderText=DialogTheme.CheckMark(DialogTheme.ColumnCheckState(count,Displays.Rows.Count))+" "+label;
            };
            Displays.RowsAdded+=delegate { update(); };
            Displays.CellValueChanged+=delegate(object sender,DataGridViewCellEventArgs e) {
                if(e.RowIndex>=0 && e.ColumnIndex==column.Index) update();
            };
            Displays.ColumnHeaderMouseClick+=delegate(object sender,DataGridViewCellMouseEventArgs e) {
                if(e.Button!=MouseButtons.Left || e.ColumnIndex!=column.Index || !Displays.EndEdit()) return;
                bool value=countChecked()!=Displays.Rows.Count;
                foreach(DataGridViewRow row in Displays.Rows) row.Cells[column.Index].Value=value;
            };
            update();
        }
        public void AddDisplay(string key,string label,bool include,bool enabled,string brightness) {
            int index=Displays.Rows.Add(include,label,enabled,brightness); Displays.Rows[index].Tag=key;
        }
    }
    public sealed class ShortcutForm : DialogForm {
        public readonly CheckBox Ctrl=new DialogCheckBox(),Alt=new DialogCheckBox(),Shift=new DialogCheckBox(),Win=new DialogCheckBox();
        public readonly ComboBox Key=new DialogComboBox(),Action=new DialogComboBox(),Preset=new DialogComboBox();
        public readonly CheckedListBox Targets=new DialogCheckedListBox();
        public ShortcutForm() {
            ProfileUi.Initialize(this,"Keyboard shortcut",600,430);
            var checks=new CheckBox[]{Ctrl,Alt,Shift,Win}; var names=new string[]{"Ctrl","Alt","Shift","Win"};
            for(int i=0;i<4;i++) { checks[i].Text=names[i]; checks[i].SetBounds(16+i*95,20,90,28); Controls.Add(checks[i]); }
            Key.SetBounds(410,20,170,28); Key.DropDownStyle=ComboBoxStyle.DropDownList;
            for(int i=65;i<=90;i++) Key.Items.Add((Keys)i);
            for(int i=112;i<=123;i++) Key.Items.Add((Keys)i);
            for(int i=48;i<=57;i++) Key.Items.Add((Keys)i);
            Key.SelectedIndex=0;
            Controls.Add(ProfileUi.Label("Action",16,70)); Action.SetBounds(210,68,370,28); Action.DropDownStyle=ComboBoxStyle.DropDownList;
            Action.Items.AddRange(new object[]{"Enable HDR","Disable HDR","Toggle HDR","Apply preset"}); Action.SelectedIndex=0;
            Controls.Add(ProfileUi.Label("Preset",16,112)); Preset.SetBounds(210,110,370,28); Preset.DropDownStyle=ComboBoxStyle.DropDownList;
            Controls.Add(ProfileUi.Label("Monitors",16,155)); Targets.SetBounds(210,153,370,155); Targets.CheckOnClick=true;
            Action.SelectedIndexChanged+=delegate { Preset.Enabled=Action.SelectedIndex==3; Targets.Enabled=Action.SelectedIndex!=3; };
            Preset.Enabled=false;
            var note=ProfileUi.Label("No monitor selection means all active HDR monitors.\r\nUnavailable shortcuts are reported when you save.",16,320,564); note.Height=48; Controls.Add(note);
            var save=ProfileUi.Button("Save",360,376); save.DialogResult=DialogResult.OK;
            var cancel=ProfileUi.Button("Cancel",475,376); cancel.DialogResult=DialogResult.Cancel;
            Controls.AddRange(new Control[]{Key,Action,Preset,Targets,save,cancel}); AcceptButton=save; CancelButton=cancel; ProfileUi.AddHeader(this,"Keyboard shortcut","Choose a key combination and the action it runs."); ProfileUi.Theme(this);
        }
        public int Modifiers { get { return (Alt.Checked?1:0)|(Ctrl.Checked?2:0)|(Shift.Checked?4:0)|(Win.Checked?8:0); }
            set { Alt.Checked=(value&1)!=0; Ctrl.Checked=(value&2)!=0; Shift.Checked=(value&4)!=0; Win.Checked=(value&8)!=0; } }
        public static string ModifierText(int value) { return (((value&2)!=0?"Ctrl+":"")+((value&1)!=0?"Alt+":"")+((value&4)!=0?"Shift+":"")+((value&8)!=0?"Win+":"")).TrimEnd('+'); }
        public void AddTarget(string key,string label,bool selected) { Targets.Items.Add(new DisplayChoice(key,label),selected); }
        public void AddPreset(string id,string label) { Preset.Items.Add(new DisplayChoice(id,label)); }
        public string[] SelectedTargets() { var keys=new List<string>(); foreach(DisplayChoice item in Targets.CheckedItems) keys.Add(item.Key); return keys.ToArray(); }
    }
    public sealed class ProfileSettingsForm : DialogForm, IMessageFilter {
        sealed class AliasCell : DataGridViewTextBoxCell {
            public override void PositionEditingControl(bool setLocation,bool setSize,Rectangle cellBounds,Rectangle cellClip,
                DataGridViewCellStyle cellStyle,bool singleVerticalBorderAdded,bool singleHorizontalBorderAdded,
                bool isFirstDisplayedColumn,bool isFirstDisplayedRow) {
                var style=new DataGridViewCellStyle(cellStyle);
                var padding=style.Padding;
                // TextRenderer reserves a sixth of the line height for glyph overhang.
                // The left-aligned grid editor already adds three pixels of its own.
                int lineHeight=TextRenderer.MeasureText("Mg",style.Font,Size.Empty,TextFormatFlags.SingleLine|TextFormatFlags.NoPadding).Height;
                padding.Left+=(int)Math.Ceiling(lineHeight/6.0)-3;
                style.Padding=padding;
                base.PositionEditingControl(setLocation,setSize,cellBounds,cellClip,style,singleVerticalBorderAdded,
                    singleHorizontalBorderAdded,isFirstDisplayedColumn,isFirstDisplayedRow);
                if(setSize) DataGridView.EditingControl.Height=lineHeight;
            }
        }
        public readonly ComboBox ExitPolicy=new DialogComboBox();
        public readonly DataGridView Monitors;
        public readonly ListView Presets=new DialogListView(),Shortcuts=new DialogListView();
        public readonly Button NewPreset,EditPreset,DeletePreset,NewShortcut,EditShortcut,DeleteShortcut;
        public readonly Button CopyDiagnosticsButton;
        internal bool DataLoaded { get; private set; }
        internal void SetDataLoaded(bool loaded) {
            DataLoaded=loaded;
            ExitPolicy.Enabled=Monitors.Enabled=Presets.Enabled=Shortcuts.Enabled=loaded;
            NewPreset.Enabled=EditPreset.Enabled=DeletePreset.Enabled=loaded;
            NewShortcut.Enabled=EditShortcut.Enabled=DeleteShortcut.Enabled=CopyDiagnosticsButton.Enabled=loaded;
        }
        readonly Label diagnosticsStatus;
        readonly System.Windows.Forms.Timer diagnosticsTimer=new System.Windows.Forms.Timer();
        Font aliasEditorFont;
        public ProfileSettingsForm() : this(null) { }
        internal ProfileSettingsForm(Panel footer) {
            ProfileUi.Initialize(this,"Profiles and shortcuts",880,footer==null?660:660-SettingsFooterHeight);
            DialogTheme.AddSettingsHeader(this,Text,"Choose what happens after a game exits, name your monitors, and manage presets and keyboard shortcuts.");
            var tabs=new DialogTabs {Bounds=new Rectangle(24,116,832,470),Anchor=AnchorStyles.Top|AnchorStyles.Bottom|AnchorStyles.Left|AnchorStyles.Right};
            var general=new Panel {Text="Automation and monitors"}; var presets=new Panel {Text="Presets"}; var shortcuts=new Panel {Text="Keyboard shortcuts"};
            tabs.TabPages.AddRange(new Panel[]{general,presets,shortcuts});
            general.Controls.Add(ProfileUi.Label("Default after game exit",16,20,230)); ExitPolicy.SetBounds(260,18,460,28);
            ExitPolicy.DropDownStyle=ComboBoxStyle.DropDownList; ExitPolicy.Items.AddRange(new object[]{"Return to SDR","Restore previous state"});
            var note=ProfileUi.Label("Manual changes take precedence until the relevant game session ends.\r\nMonitor aliases appear in the tray and editors. Disconnected monitors keep their saved settings.",16,62,710); note.Height=60; general.Controls.Add(note);
            Monitors=ProfileUi.Grid(16,135,710,260);
            Monitors.Columns.Add(new DataGridViewTextBoxColumn{Name="Monitor",HeaderText="Monitor",ReadOnly=true});
            Monitors.Columns.Add(new DataGridViewTextBoxColumn{CellTemplate=new AliasCell(),Name="Alias",HeaderText="Alias",MaxInputLength=80});
            Monitors.EditingControlShowing+=SetAliasEditorFont;
            Monitors.CellBeginEdit+=delegate { Application.AddMessageFilter(this); };
            Monitors.CellEndEdit+=delegate { Application.RemoveMessageFilter(this); };
            general.Controls.AddRange(new Control[]{ExitPolicy,Monitors});
            foreach(ListView list in new ListView[]{Presets,Shortcuts}) {
                list.SetBounds(16,16,710,365); list.Anchor=AnchorStyles.Top|AnchorStyles.Bottom|AnchorStyles.Left|AnchorStyles.Right;
                list.View=View.Details; list.FullRowSelect=true; list.MultiSelect=false; list.HideSelection=false; list.Columns.Add("Name",680);
            }
            NewPreset=ProfileUi.Button("New...",16,408); EditPreset=ProfileUi.Button("Edit...",131,408); DeletePreset=ProfileUi.Button("Delete",246,408);
            presets.Controls.AddRange(new Control[]{Presets,NewPreset,EditPreset,DeletePreset});
            NewShortcut=ProfileUi.Button("New...",16,408); EditShortcut=ProfileUi.Button("Edit...",131,408); DeleteShortcut=ProfileUi.Button("Delete",246,408);
            shortcuts.Controls.AddRange(new Control[]{Shortcuts,NewShortcut,EditShortcut,DeleteShortcut});
            if(footer==null) footer=CreateSettingsFooter();
            CopyDiagnosticsButton=ProfileUi.Button("Copy diagnostics",24,12,180);
            CopyDiagnosticsButton.Height=38;
            diagnosticsStatus=DialogTheme.Caption("",220,17,400,28);
            footer.Controls.AddRange(new Control[]{CopyDiagnosticsButton,diagnosticsStatus});
            tabs.TabIndex=0; footer.TabIndex=1;
            diagnosticsTimer.Interval=3000;
            diagnosticsTimer.Tick+=delegate { SetDiagnosticsCopied(false); };
            Controls.Add(tabs); ProfileUi.Theme(this);
            Load+=delegate { LayoutEditors(); };
            SizeChanged+=delegate { LayoutEditors(); };
            tabs.SizeChanged+=delegate { LayoutEditors(); };
            tabs.SelectedIndexChanged+=delegate { LayoutEditors(); };
        }
        void SetAliasEditorFont(object sender,DataGridViewEditingControlShowingEventArgs e) {
            // Let the cell reserve the whole rendered line, including descenders.
            e.Control.AutoSize=false;
            // The cell's TextRenderer rounds fractional pixel heights up. The native
            // text box rounds to the nearest pixel when given the same point size.
            var font=e.CellStyle.Font;
            using(var graphics=Monitors.CreateGraphics()) {
                float height=(float)Math.Ceiling(font.SizeInPoints*graphics.DpiY/72f);
                var previous=aliasEditorFont;
                aliasEditorFont=new Font(font.FontFamily,height,font.Style,GraphicsUnit.Pixel,font.GdiCharSet,font.GdiVerticalFont);
                e.CellStyle.Font=aliasEditorFont;
                if(previous!=null) previous.Dispose();
            }
        }
        public void SetDiagnosticsCopied(bool copied) {
            diagnosticsTimer.Stop();
            diagnosticsStatus.Text=copied ? "Copied to clipboard" : "";
            if(copied) diagnosticsTimer.Start();
        }
        bool IMessageFilter.PreFilterMessage(ref Message message) {
            // Labels and empty grid space can receive clicks without moving keyboard focus.
            const int LeftDown=0x0201,RightDown=0x0204,MiddleDown=0x0207,NonClientLeftDown=0x00a1;
            if(message.Msg==LeftDown || message.Msg==RightDown || message.Msg==MiddleDown || message.Msg==NonClientLeftDown) {
                var editor=Monitors.EditingControl;
                if(editor!=null && message.HWnd!=editor.Handle) Monitors.EndEdit();
            }
            return false;
        }
        protected override void Dispose(bool disposing) {
            if(disposing) { Application.RemoveMessageFilter(this); diagnosticsTimer.Dispose(); }
            base.Dispose(disposing);
            if(disposing && aliasEditorFont!=null) { aliasEditorFont.Dispose(); aliasEditorFont=null; }
        }
        void LayoutEditors() {
            if(Monitors==null || Monitors.Parent==null) return;
            Func<int,int> px=value=>(int)Math.Round(value*ExitPolicy.Top/18.0);
            var area=Monitors.Parent.ClientSize;
            Monitors.SetBounds(px(16),px(135),Math.Max(px(300),area.Width-px(32)),Math.Max(px(100),area.Height-px(151)));
            foreach(ListView list in new ListView[]{Presets,Shortcuts}) {
                if(list.Parent!=null) { var size=list.Parent.ClientSize; list.SetBounds(px(16),px(16),Math.Max(px(300),size.Width-px(32)),Math.Max(px(100),size.Height-px(100))); }
            }
            var p=Presets.Parent.ClientSize; var s=Shortcuts.Parent.ClientSize;
            NewPreset.Top=EditPreset.Top=DeletePreset.Top=p.Height-px(54);
            NewShortcut.Top=EditShortcut.Top=DeleteShortcut.Top=s.Height-px(54);
        }
        public void AddMonitor(MonitorAlias monitor) {
            string name=String.IsNullOrEmpty(monitor.ModelName) ? "Monitor "+monitor.Key.Substring(0,8) : monitor.ModelName;
            int i=Monitors.Rows.Add(monitor.Disconnected ? name+" (disconnected)" : name,monitor.Alias);
            Monitors.Rows[i].Tag=monitor;
        }
        public void AddPreset(string id,string name) { var item=new ListViewItem(name); item.Tag=id; Presets.Items.Add(item); }
        public void AddShortcut(string id,string name) { var item=new ListViewItem(name); item.Tag=id; Shortcuts.Items.Add(item); }
    }
    public sealed class MonitorAlias {
        public string Key,ModelName,Alias;
        public bool Disconnected;
    }
    public sealed class GeneralSettingsEdit {
        public int ExitPolicy;
        public MonitorAlias[] Monitors;
    }
    // Data crossing between the settings STA and the tray never contains WinForms controls.
    public sealed class MonitorBrightness {
        public string Name,DisplayId,PreferenceKey,Mode,Status,Runtime;
        public uint Level,CurrentLevel,LastUsedLevel,DayLevel,NightLevel;
        public int DayStart,NightStart;
        public bool Restore,Enforce,Busy,Saving,LevelEdited,HdrOff;
        public Guid EditId;
        public static MonitorBrightness Capture(SdrBrightnessForm form) {
            return new MonitorBrightness {
                DisplayId=form.DisplayId,PreferenceKey=form.PreferenceKey,Level=form.SelectedLevel,EditId=form.EditId,
                Restore=form.Restore.Checked,Enforce=form.Enforce.Checked,
                LevelEdited=form.LevelEdited,Mode=form.SwitchingMode,DayLevel=form.DayLevel,NightLevel=form.NightLevel,
                DayStart=(int)form.DayStart.Value.TimeOfDay.TotalMinutes,NightStart=(int)form.NightStart.Value.TimeOfDay.TotalMinutes
            };
        }
        public void Refresh(SdrBrightnessForm editor) {
            if(CurrentLevel!=0) editor.InitializeLevel(CurrentLevel);
            editor.SetReadoutLevel(CurrentLevel!=0 ? CurrentLevel : LastUsedLevel);
            editor.Runtime.Text=Runtime;
            editor.RefreshAvailability(CurrentLevel!=0,Busy,Status,Saving,HdrOff);
        }
    }

    internal sealed class TabSaveStatus : SaveStatusLabel {
        int revision;
        internal TabSaveStatus(Form page) {
            Name="SaveStatus";
            TextAlign=ContentAlignment.MiddleLeft;
            SetBounds(page.ClientSize.Width-144,24,120,30);
            Anchor=AnchorStyles.Top|AnchorStyles.Right;
            if(!SystemInformation.HighContrast) { ForeColor=DialogTheme.Muted; BackColor=page.BackColor; }
            page.Controls.Add(this);
        }
        internal int BeginEdit(bool saving) {
            ClearFeedback();
            if(saving) BeginSaving();
            return ++revision;
        }
        internal void Confirm(int edit) {
            if(edit!=revision) return;
            Confirm(DialogTheme.SavedText);
        }
        internal void EndDispatch(int edit) {
            if(edit==revision) ClearUnconfirmed();
        }
    }
    public sealed class SettingsForm : DialogForm {
        public readonly DialogTabs Sections=new DialogTabs();
        public readonly GameListsForm Games;
        public readonly ProfileSettingsForm Profiles;
        internal readonly TabSaveStatus GameSaveStatus,ProfileSaveStatus;
        public readonly ComboBox DisplayPicker=new DialogComboBox();
        public SdrBrightnessForm Brightness { get; private set; }
        public string ActiveBrightnessId { get { return Sections.SelectedIndex==0 && Brightness!=null ? Brightness.DisplayId : null; } }
        internal event Action<string,object> Command;
        readonly Panel brightnessBody=new Panel {Dock=DockStyle.Fill};
        readonly Label empty=DialogTheme.Caption("",24,20,640,60);
        MonitorBrightness[] displays=new MonitorBrightness[0];
        string selectedId;
        bool updatingPicker;
        Size pageSize;
        readonly Panel footer;
        internal readonly Panel AutomaticOffNotice;
        internal readonly DialogButton EnableAutomatic=new DialogButton {Text="Enable auto-switching",Dock=DockStyle.Right,Width=182};
        readonly Panel hdrOffNotice;
        readonly DialogButton enableHdr=new DialogButton {Text="Enable HDR",Dock=DockStyle.Right,Width=182};
        readonly string settingsKey;
        const string PlacementValue="SettingsWindowPlacement";

        public SettingsForm() : this(@"HKEY_CURRENT_USER\Software\HdrContextMenu") { }
        internal SettingsForm(string settingsKey) {
            this.settingsKey=settingsKey;
            ProfileUi.Initialize(this,"HDR Control settings",904,664);
            MaximizeBox=false;
            Padding=new Padding(12,12,12,0);
            footer=CreateSettingsFooter();
            var actionSpace=new Size(footer.ClientSize.Width-148,footer.Height);
            var gameActions=new Panel {Size=actionSpace,Anchor=AnchorStyles.Top|AnchorStyles.Left|AnchorStyles.Right,Visible=false};
            var profileActions=new Panel {Size=actionSpace,Anchor=gameActions.Anchor,Visible=false};
            footer.Controls.AddRange(new Control[]{gameActions,profileActions});
            Games=new GameListsForm(gameActions,settingsKey); Profiles=new ProfileSettingsForm(profileActions);
            GameSaveStatus=new TabSaveStatus(Games); ProfileSaveStatus=new TabSaveStatus(Profiles);
            var content=new Panel {Dock=DockStyle.Fill,AutoScroll=true,TabIndex=0};
            footer.TabIndex=1;
            Sections.Size=new Size(ClientSize.Width-Padding.Horizontal,ClientSize.Height-Padding.Vertical-footer.Height);
            content.Controls.Add(Sections); Controls.Add(content); content.BringToFront();
            Load+=delegate {
                // Dock to the scrollable display area so a vertical scrollbar
                // reduces the page width without also forcing a horizontal bar.
                pageSize=new Size(Sections.Width-SystemInformation.VerticalScrollBarWidth,Sections.Height);
                Sections.Dock=DockStyle.Fill;
                RestorePlacement();
                LocationChanged+=delegate { UpdateResizeLimit(); };
            };
            var brightness=new Panel {Text="SDR brightness"};
            var games=new Panel {Text="Game lists"};
            var profiles=new Panel {Text="Profiles and shortcuts"};
            Sections.TabPages.AddRange(new Panel[]{brightness,games,profiles});
            var displayBar=new Panel {Dock=DockStyle.Top,Height=100,Width=896};
            DialogTheme.AddSettingsHeader(displayBar,brightness.Text,"Adjust SDR content brightness and scheduling for the selected HDR display.");
            var displayLabel=ProfileUi.Label("Display",456,28,70);
            displayLabel.Anchor=AnchorStyles.Top|AnchorStyles.Right;
            displayBar.Controls.Add(displayLabel);
            DisplayPicker.DropDownStyle=ComboBoxStyle.DropDownList;
            DisplayPicker.AccessibleName="Display for SDR brightness";
            DisplayPicker.SetBounds(534,20,338,34);
            DisplayPicker.Anchor=AnchorStyles.Top|AnchorStyles.Right;
            displayBar.Controls.Add(DisplayPicker);
            brightnessBody.Controls.Add(empty);
            brightness.Controls.Add(brightnessBody); brightness.Controls.Add(displayBar);
            DialogTheme.Apply(this);
            AutomaticOffNotice=AddNotice(games,"Auto-switching is off. Game detection is paused.",EnableAutomatic);
            hdrOffNotice=AddNotice(brightness,"HDR is off. Enable HDR to adjust SDR brightness.",enableHdr);
            enableHdr.Click+=delegate {
                enableHdr.Enabled=false;
                Request("EnableHdr",selectedId);
            };
            Games.Embed(games); Profiles.Embed(profiles);
            Games.BringToFront();
            EnableAutomatic.Click+=delegate {
                EnableAutomatic.Enabled=false;
                Request("EnableAutomatic",null);
            };
            Games.UseCommunityApps.Click+=delegate {
                Games.UseCommunityApps.Enabled=false;
                Request("SetCommunityApps",Games.UseCommunityApps.Checked);
            };
            Profiles.SetDataLoaded(false);
            Sections.SelectedIndexChanged+=delegate {
                gameActions.Visible=Sections.SelectedIndex==1;
                profileActions.Visible=Sections.SelectedIndex==2;
                if(Sections.SelectedIndex!=0 && Brightness!=null) Brightness.CommitEdits();
                if(Sections.SelectedIndex==2 && !Profiles.DataLoaded) Request("LoadProfiles",null);
            };
            Profiles.ExitPolicy.SelectedIndexChanged+=delegate { SaveGeneralSettings(); };
            Profiles.Monitors.CellValueChanged+=delegate(object sender,DataGridViewCellEventArgs e) {
                if(e.RowIndex>=0 && e.ColumnIndex==Profiles.Monitors.Columns["Alias"].Index) SaveGeneralSettings();
            };
            Profiles.Monitors.VisibleChanged+=delegate { if(!Profiles.Monitors.Visible) Profiles.Monitors.EndEdit(); };
            Deactivate+=delegate { Profiles.Monitors.EndEdit(); };
            Profiles.CopyDiagnosticsButton.Click+=delegate { Request("CopyDiagnostics",null); };
            BindProfileButton(Profiles.NewPreset,"NewPreset",Profiles.Presets);
            BindProfileButton(Profiles.EditPreset,"EditPreset",Profiles.Presets);
            BindProfileButton(Profiles.DeletePreset,"DeletePreset",Profiles.Presets);
            Profiles.Presets.ItemActivate+=delegate {
                var selected=Profiles.Presets.SelectedItems;
                if(selected.Count==1) Request("ApplyPreset",(string)selected[0].Tag);
            };
            BindProfileButton(Profiles.NewShortcut,"NewShortcut",Profiles.Shortcuts);
            BindProfileButton(Profiles.EditShortcut,"EditShortcut",Profiles.Shortcuts);
            BindProfileButton(Profiles.DeleteShortcut,"DeleteShortcut",Profiles.Shortcuts);
            DisplayPicker.SelectedIndexChanged+=delegate {
                if(updatingPicker || DisplayPicker.SelectedIndex<0) return;
                selectedId=displays[DisplayPicker.SelectedIndex].DisplayId;
                RefreshBrightness();
            };
            FormClosing+=delegate {
                if(Brightness!=null) Brightness.CommitEdits();
                Profiles.Monitors.EndEdit(); Games.CommitPendingClicks();
            };
            FormClosed+=delegate {
                if(settingsKey==null || StartPosition==FormStartPosition.Manual) return;
                var bounds=WindowState==FormWindowState.Normal ? Bounds : RestoreBounds;
                try {
                    Registry.SetValue(settingsKey,PlacementValue,new string[]{bounds.X.ToString(),bounds.Y.ToString(),bounds.Height.ToString(),bounds.Width.ToString()},RegistryValueKind.MultiString);
                } catch(UnauthorizedAccessException) { } catch(System.Security.SecurityException) { } catch(IOException) { }
            };
            SetDisplays(displays);
        }
        static Panel AddNotice(Panel page,string message,DialogButton action) {
            var notice=new Panel {Dock=DockStyle.Top,Height=46,Padding=new Padding(12,5,12,5),Visible=false};
            var label=new Label {Text=message,Dock=DockStyle.Fill,TextAlign=ContentAlignment.MiddleLeft};
            notice.Controls.Add(label); notice.Controls.Add(action);
            page.Controls.Add(notice);
            DialogTheme.Apply(notice);
            notice.BackColor=label.BackColor=DialogTheme.Surface;
            label.ForeColor=Color.FromArgb(255,215,138);
            return notice;
        }
        void UpdateResizeLimit() {
            if(pageSize.IsEmpty || Disposing) return;
            var area=Screen.FromControl(this).WorkingArea;
            var previous=Size;
            UpdateResizeLimit(area.Size);
            if(Size!=previous && StartPosition!=FormStartPosition.Manual)
                Location=new Point(Math.Max(area.Left,Math.Min(Left,area.Right-Width)),Math.Max(area.Top,Math.Min(Top,area.Bottom-Height)));
        }
        void UpdateResizeLimit(Size workArea) {
            int height=pageSize.Height;
            if(Brightness!=null) {
                int editorHeight=Brightness.SettingsColumns.Height;
                height=Math.Max(height,Sections.TabPages[0].Top+DisplayPicker.Parent.Bottom+editorHeight);
            }
            var content=(Panel)Sections.Parent;
            content.AutoScrollMinSize=new Size(pageSize.Width,height);
            var minimum=SizeFromClientSize(new Size(pageSize.Width+Padding.Horizontal,height+Padding.Vertical+footer.Height));
            // On a smaller monitor, leave room for the one unavoidable scrollbar.
            if(minimum.Height>workArea.Height) minimum.Width+=SystemInformation.VerticalScrollBarWidth;
            if(minimum.Width>workArea.Width) minimum.Height+=SystemInformation.HorizontalScrollBarHeight;
            MinimumSize=new Size(Math.Min(minimum.Width,workArea.Width),Math.Min(minimum.Height,workArea.Height));
        }
        void RestorePlacement() {
            string[] saved=null;
            if(settingsKey!=null && StartPosition!=FormStartPosition.Manual) {
                try { saved=Registry.GetValue(settingsKey,PlacementValue,null) as string[]; }
                catch(UnauthorizedAccessException) { } catch(System.Security.SecurityException) { } catch(IOException) { }
            }
            int x=0,y=0,height=0;
            bool restore=saved!=null && (saved.Length==3 || saved.Length==4) && int.TryParse(saved[0],out x) &&
                int.TryParse(saved[1],out y) && int.TryParse(saved[2],out height) && height>0;
            var area=(restore ? Screen.FromPoint(new Point(x,y)) : Screen.FromControl(this)).WorkingArea;
            int width=Math.Min(Width,area.Width);
            UpdateResizeLimit(area.Size);
            int savedWidth;
            if(restore && saved.Length==4 && int.TryParse(saved[3],out savedWidth) && savedWidth>0)
                width=Math.Max(MinimumSize.Width,Math.Min(savedWidth,area.Width));
            if(!restore) height=Math.Max(Height,area.Height*85/100);
            Size=new Size(width,Math.Max(MinimumSize.Height,Math.Min(height,area.Height)));
            if(StartPosition==FormStartPosition.Manual) return;
            Location=restore
                ? new Point(Math.Max(area.Left,Math.Min(x,area.Right-Width)),Math.Max(area.Top,Math.Min(y,area.Bottom-Height)))
                : new Point(area.Left+(area.Width-Width)/2,area.Top+(area.Height-Height)/2);
        }
        void SaveGeneralSettings() {
            if(!Profiles.DataLoaded) return;
            var monitors=new List<MonitorAlias>();
            foreach(DataGridViewRow row in Profiles.Monitors.Rows) {
                var monitor=(MonitorAlias)row.Tag;
                monitors.Add(new MonitorAlias {Key=monitor.Key,ModelName=monitor.ModelName,Alias=Convert.ToString(row.Cells["Alias"].Value)});
            }
            Request("SaveGeneral",new GeneralSettingsEdit {ExitPolicy=Profiles.ExitPolicy.SelectedIndex,Monitors=monitors.ToArray()});
        }
        void BindProfileButton(Button button,string action,ListView list) {
            button.Click+=delegate { Request(action,list.SelectedItems.Count==0 ? "" : (string)list.SelectedItems[0].Tag); };
        }
        public void AppliedBrightness(MonitorBrightness edit) {
            if(Brightness!=null && Brightness.EditId==edit.EditId) Brightness.ShowSaved();
        }
        public void RejectedBrightness(MonitorBrightness edit) {
            if(Brightness!=null && Brightness.EditId==edit.EditId) Brightness.SaveStatus.ClearFeedback();
        }
        void Request(string command,object value) { if(Command!=null) Command(command,value); }

        public void SelectDisplay(string id) {
            selectedId=id;
            Sections.SelectedIndex=0;
            RefreshBrightness();
        }
        internal void SetAutomaticSwitching(bool enabled) {
            AutomaticOffNotice.Visible=!enabled;
            EnableAutomatic.Enabled=true;
        }
        public void SetDisplays(MonitorBrightness[] current) {
            displays=current;
            updatingPicker=true;
            try {
                if(selectedId==null && displays.Length>0) selectedId=displays[0].DisplayId;
                var names=Array.ConvertAll(displays,d=>d.Name);
                bool changed=DisplayPicker.Items.Count!=names.Length;
                for(int i=0;!changed && i<names.Length;i++) changed=!Equals(DisplayPicker.Items[i],names[i]);
                if(changed) { DisplayPicker.Items.Clear(); DisplayPicker.Items.AddRange(names); }
            } finally { updatingPicker=false; }
            RefreshBrightness();
        }
        void RefreshBrightness() {
            int index=Array.FindIndex(displays,item=>item.DisplayId==selectedId);
            updatingPicker=true;
            try { DisplayPicker.SelectedIndex=index; DisplayPicker.Enabled=displays.Length>0; }
            finally { updatingPicker=false; }
            var d=index<0 ? null : displays[index];
            hdrOffNotice.Visible=d!=null && d.HdrOff;
            enableHdr.Enabled=d!=null && d.HdrOff && !d.Busy;
            if(Brightness!=null && (d==null || Brightness.DisplayId!=d.DisplayId || Brightness.PreferenceKey!=d.PreferenceKey)) {
                Brightness.CommitEdits();
                Brightness.Dispose(); Brightness=null;
            }
            empty.Visible=d==null;
            if(d==null) {
                empty.Text=displays.Length==0 ? "Connect an HDR-capable display to adjust SDR brightness." : "This display is disconnected. Choose another display above.";
                UpdateResizeLimit();
                return;
            }
            if(Brightness==null) {
                var editor=new SdrBrightnessForm(d.Name,d.DisplayId,d.PreferenceKey,d.Level,d.Restore);
                editor.LoadSettings(d.DayLevel,d.NightLevel,d.Mode,d.DayStart,d.NightStart,d.Enforce);
                editor.SettingsEdited+=delegate { Request("SaveBrightness",MonitorBrightness.Capture(editor)); };
                editor.Calibrate.Click+=delegate { Request("Calibrate",null); };
                editor.HdrSettings.Click+=delegate { Request("HdrSettings",null); };
                editor.NightLightSettings.Click+=delegate { Request("NightLight",null); };
                editor.LocationSettings.Click+=delegate { Request("Location",null); };
                Brightness=editor;
                editor.UseSettingsLayout();
                editor.Embed(brightnessBody);
                editor.SettingsColumns.SizeChanged+=delegate { UpdateResizeLimit(); };
                UpdateResizeLimit();
            }
            d.Refresh(Brightness);
            UpdateResizeLimit();
        }
    }

    // The tray owns actions and data; this window owns only its controls. Queue
    // immutable snapshots and button requests rather than crossing UI threads.
    public sealed class SettingsWindow : IDisposable, IWin32Window {
        public sealed class ActionButton {
            public volatile bool Enabled=true;
            public volatile string Text="";
            public event EventHandler Click;
            internal void Raise() { if(Click!=null) Click(this,EventArgs.Empty); }
        }
        sealed class Row {
            public readonly string Section,Executable,Status,Detected;
            public readonly bool Enabled,CanRemove;
            public Row(string section,string executable,string status,string detected,bool enabled,bool canRemove) { Section=section; Executable=executable; Status=status; Detected=detected; Enabled=enabled; CanRemove=canRemove; }
            public void AddTo(GameListsForm form) { form.AddRow(Section,Executable,Status,Detected,Enabled,CanRemove); }
        }
        sealed class Request {
            public int Action;
            public string Executable;
            public string[] Games;
            public bool? Enabled;
            public string Command;
            public object Data;
            public Action ConfirmSave,EndSaveDispatch;
        }
        public readonly ActionButton RefreshButton=new ActionButton(),UpdateCommunityButton=new ActionButton(),EditCustomButton=new ActionButton(),
            AddRunningButton=new ActionButton(),AddGameButton=new ActionButton(),EditRuleButton=new ActionButton(),LaunchButton=new ActionButton(),ShortcutButton=new ActionButton(),RemoveButton=new ActionButton();
        public event Action<string[],bool> EnableRequested;
        public event Action<string,object> CommandRequested;
        // The tray calls this only after persistence succeeds. A delayed operation can
        // retain its own callback across dispatches, including closing/reopening settings.
        public Action SaveConfirmation { get; private set; }
        readonly System.Collections.Concurrent.ConcurrentQueue<Action<SettingsForm>> updates=new System.Collections.Concurrent.ConcurrentQueue<Action<SettingsForm>>();
        IntPtr handle;
        public IntPtr Handle { get { return handle; } }
        volatile string activeBrightnessId;
        public string ActiveBrightnessId { get { return IsDisposed ? null : activeBrightnessId; } }

        public void SelectDisplay(string id) { updates.Enqueue(window=>window.SelectDisplay(id)); }
        public void SetAutomaticSwitching(bool enabled) { updates.Enqueue(window=>window.SetAutomaticSwitching(enabled)); }
        public void SetCommunityApps(bool enabled) {
            updates.Enqueue(window=>{
                window.Games.UseCommunityApps.Checked=enabled;
                window.Games.UseCommunityApps.Enabled=true;
            });
        }
        public void SetDisplays(MonitorBrightness[] displays) { updates.Enqueue(window=>window.SetDisplays(displays)); }
        public void AppliedBrightness(MonitorBrightness edit) {
            updates.Enqueue(window=>window.AppliedBrightness(edit));
        }
        public void RejectedBrightness(MonitorBrightness edit) {
            updates.Enqueue(window=>window.RejectedBrightness(edit));
        }
        public void SetGeneral(int exitPolicy,MonitorAlias[] monitors) {
            updates.Enqueue(window=>{
                var profile=window.Profiles;
                if(profile.DataLoaded) return; // A second tab visit can queue a duplicate initial load.
                profile.ExitPolicy.SelectedIndex=exitPolicy;
                profile.Monitors.Rows.Clear();
                foreach(var m in monitors) profile.AddMonitor(m);
                profile.SetDataLoaded(true);
            });
        }
        public void SetProfileLists(DisplayChoice[] presets,DisplayChoice[] shortcuts) {
            updates.Enqueue(window=>{
                var profile=window.Profiles;
                profile.Presets.Items.Clear();
                foreach(var p in presets) profile.AddPreset(p.Key,p.Label);
                profile.Shortcuts.Items.Clear();
                foreach(var s in shortcuts) profile.AddShortcut(s.Key,s.Label);
            });
        }
        public void DiagnosticsCopied(bool copied) { updates.Enqueue(window=>window.Profiles.SetDiagnosticsCopied(copied)); }
        readonly ActionButton[] actions;
        readonly Func<SettingsForm> createForm;
        readonly System.Windows.Forms.Timer dispatchTimer=new System.Windows.Forms.Timer();
        readonly System.Collections.Concurrent.ConcurrentQueue<Request> requests=new System.Collections.Concurrent.ConcurrentQueue<Request>();
        readonly System.Collections.Generic.List<Row> pendingRows=new System.Collections.Generic.List<Row>();
        static readonly Row[] emptyRows=new Row[0];
        volatile Row[] snapshot=emptyRows;
        volatile string selectedExecutable="";
        string requestExecutable;
        volatile bool disposed,finished;
        bool dispatching;
        int busy,activate,pendingToggles;
        Thread uiThread;
        public Exception Error { get; private set; }
        public event EventHandler Failed;
        public bool IsDisposed { get { return disposed || finished; } }
        public string SelectedExecutable { get { return requestExecutable ?? selectedExecutable; } }
        public SettingsWindow() : this(delegate {return new SettingsForm();}) { }
        internal SettingsWindow(Func<SettingsForm> createForm) {
            this.createForm=createForm;
            actions=new ActionButton[]{RefreshButton,UpdateCommunityButton,EditCustomButton,AddRunningButton,AddGameButton,EditRuleButton,LaunchButton,ShortcutButton,RemoveButton};
            dispatchTimer.Interval=50;
            dispatchTimer.Tick+=delegate {
                if(disposed || dispatching) return;
                if(finished && requests.IsEmpty) {
                    Dispose();
                    if(Error!=null && Failed!=null) Failed(this,EventArgs.Empty);
                    return;
                }
                Request request;
                if(!requests.TryDequeue(out request)) return;
                dispatching=true; requestExecutable=request.Executable;
                SaveConfirmation=request.ConfirmSave;
                try {
                    if(request.Enabled.HasValue) {if(EnableRequested!=null) EnableRequested(request.Games,request.Enabled.Value);}
                    else if(request.Command!=null) { if(CommandRequested!=null) CommandRequested(request.Command,request.Data); }
                    else actions[request.Action].Raise();
                }
                finally {
                    if(request.EndSaveDispatch!=null) request.EndSaveDispatch();
                    SaveConfirmation=null; requestExecutable=null; dispatching=false;
                    if(request.Enabled.HasValue) Interlocked.Decrement(ref pendingToggles);
                    else if(request.Command==null) Interlocked.Exchange(ref busy,0);
                }
            };
        }
        public void ClearRows() { pendingRows.Clear(); }
        public void AddRow(string section,string executable,string status,string detected,bool enabled=true,bool canRemove=true) { pendingRows.Add(new Row(section,executable,status,detected,enabled,canRemove)); }
        public void FinishRows() { snapshot=pendingRows.ToArray(); }
        public void Show() {
            if(IsDisposed) return;
            if(uiThread==null) {
                uiThread=new Thread(Run); uiThread.IsBackground=true; uiThread.Name="HDR settings";
                uiThread.SetApartmentState(ApartmentState.STA); uiThread.Start(); dispatchTimer.Start();
            }
            Activate();
        }
        public void Activate() { Interlocked.Exchange(ref activate,1); }
        void TrackSave(Request request,TabSaveStatus status,bool immediate) {
            int revision=status.BeginEdit(immediate);
            request.ConfirmSave=delegate { if(!IsDisposed) updates.Enqueue(window=>status.Confirm(revision)); };
            if(immediate) request.EndSaveDispatch=delegate { if(!IsDisposed) updates.Enqueue(window=>status.EndDispatch(revision)); };
        }
        void Run() {
            try {
                using(var window=createForm()) using(var timer=new System.Windows.Forms.Timer {Interval=30}) {
                    var form=window.Games;
                    window.Command+=delegate(string command,object data) {
                        var request=new Request {Command=command,Data=data};
                        switch(command) {
                            case "SaveBrightness": window.Brightness.SaveStatus.BeginSaving(); break;
                            case "SetCommunityApps": TrackSave(request,window.GameSaveStatus,true); break;
                            case "SaveGeneral": TrackSave(request,window.ProfileSaveStatus,true); break;
                            case "NewPreset": case "EditPreset": case "DeletePreset":
                            case "NewShortcut": case "EditShortcut": case "DeleteShortcut":
                                TrackSave(request,window.ProfileSaveStatus,false); break;
                        }
                        requests.Enqueue(request);
                    };
                    var buttons=new Button[]{form.RefreshButton,form.UpdateCommunityButton,form.EditCustomButton,form.AddRunningButton,form.AddGameButton};
                    var menuItems=new ToolStripMenuItem[]{form.EditRuleButton,form.LaunchButton,form.ShortcutButton,form.RemoveButton};
                    form.EnableRequested+=delegate(string[] games,bool enabled) {
                        Interlocked.Increment(ref pendingToggles);
                        var request=new Request {Games=games,Enabled=enabled};
                        TrackSave(request,window.GameSaveStatus,true);
                        requests.Enqueue(request);
                    };
                    for(int i=0;i<actions.Length;i++) {
                        int index=i;
                        EventHandler click=delegate {
                            if(Interlocked.CompareExchange(ref busy,1,0)!=0) return;
                            form.AllowToggle=false;
                            var request=new Request {Action=index,Executable=form.SelectedExecutable};
                            if(actions[index]!=RefreshButton && actions[index]!=EditCustomButton)
                                TrackSave(request,window.GameSaveStatus,false);
                            requests.Enqueue(request);
                        };
                        if(i<buttons.Length) buttons[i].Click+=click;
                        else menuItems[i-buttons.Length].Click+=click;
                    }
                    Row[] displayed=emptyRows;
                    Action apply=delegate {
                        if(disposed) {window.Close();return;}
                        Action<SettingsForm> update;
                        while(updates.TryDequeue(out update)) update(window);
                        activeBrightnessId=window.ActiveBrightnessId;
                        bool saving=Volatile.Read(ref pendingToggles)>0;
                        Row[] current=snapshot;
                        if(!saving && !Object.ReferenceEquals(displayed,current)) {
                            form.ClearRows();
                            foreach(var row in current) row.AddTo(form);
                            form.FinishRows(); displayed=current;
                        }
                        selectedExecutable=form.SelectedExecutable;
                        form.AllowToggle=Volatile.Read(ref busy)==0;
                        for(int i=0;i<actions.Length;i++) {
                            bool enabled=actions[i].Enabled && form.AllowToggle;
                            string text=actions[i].Text;
                            if(i<buttons.Length) {
                                if(buttons[i].Enabled!=enabled) buttons[i].Enabled=enabled;
                                if(text.Length>0 && buttons[i].Text!=text) buttons[i].Text=text;
                            } else {
                                var item=menuItems[i-buttons.Length];
                                enabled=enabled && selectedExecutable.Length>0 && (item!=form.RemoveButton || form.CanRemoveSelected);
                                if(item.Enabled!=enabled) item.Enabled=enabled;
                                if(text.Length>0 && item.Text!=text) item.Text=text;
                            }
                        }
                        if(Interlocked.Exchange(ref activate,0)!=0) {
                            if(window.WindowState==FormWindowState.Minimized) window.WindowState=FormWindowState.Normal;
                            window.Activate();
                        }
                    };
                    timer.Tick+=delegate {apply();};
                    window.Shown+=delegate {
                        handle=window.Handle;
                        apply(); timer.Start();
                        if(Object.ReferenceEquals(snapshot,emptyRows)) requests.Enqueue(new Request {Command="LoadGames"});
                    };
                    if(disposed) return;
                    Application.Run(window);
                }
            } catch(Exception error) {Error=error;}
            finally {handle=IntPtr.Zero; finished=true;}
        }
        public void Dispose() {
            if(disposed) return;
            disposed=true; dispatchTimer.Dispose();
            // The window's own timer closes it, without waiting on the tray UI.
        }
    }
}
