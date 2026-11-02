using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Interop;
using System.Windows.Input;
using System.Windows.Markup;
using System.Windows.Media;

namespace LocalHdrMenu {
    // Styles Microsoft's Out-GridView in its own process. Enumeration, filtering,
    // virtualization, sorting, keyboard handling and selection remain Microsoft's.
    public static class ProcessGridTheme {
        [DllImport("dwmapi.dll")] static extern int DwmSetWindowAttribute(IntPtr window,int attribute,ref int value,int size);
        static readonly Brush Background=Brush("#181A1D"),Surface=Brush("#222529"),Text=Brush("#EDF0F3"),Muted=Brush("#A0A8B2"),Edge=Brush("#3B4047"),Accent=Brush("#89D6BE");
        static bool installed;
        static Brush Brush(string color) {var brush=(SolidColorBrush)new BrushConverter().ConvertFromString(color);brush.Freeze();return brush;}
        public static void Install() {
            if(installed) return;
            installed=true;
            EventManager.RegisterClassHandler(typeof(Window),FrameworkElement.LoadedEvent,new RoutedEventHandler(WindowLoaded));
            EventManager.RegisterClassHandler(typeof(FrameworkElement),FrameworkElement.LoadedEvent,new RoutedEventHandler(ControlLoaded));
            EventManager.RegisterClassHandler(typeof(ListViewItem),Control.MouseDoubleClickEvent,new MouseButtonEventHandler(RowDoubleClick));
        }
        static void RowDoubleClick(object sender,MouseButtonEventArgs args) {
            if(args.ChangedButton!=MouseButton.Left) return;
            var row=sender as ListViewItem;
            if(row==null || !row.IsSelected || !(ItemsControl.ItemsControlFromItemContainer(row) is ListView)) return;
            var window=Window.GetWindow(row);
            if(window==null || !window.IsVisible || !window.Resources.Contains("HdrGridTheme")) return;
            var ok=FindDefaultButton(window);
            if(ok==null || !ok.IsEnabled) return;
            args.Handled=true;
            // Use the built-in acceptance path so Out-GridView returns the selected object.
            ok.RaiseEvent(new RoutedEventArgs(ButtonBase.ClickEvent));
        }
        static Button FindDefaultButton(DependencyObject root) {
            var button=root as Button;if(button!=null && button.IsDefault) return button;
            for(int i=0;i<VisualTreeHelper.GetChildrenCount(root);i++) {
                var found=FindDefaultButton(VisualTreeHelper.GetChild(root,i));if(found!=null) return found;
            }
            return null;
        }
        static void WindowLoaded(object sender,RoutedEventArgs args) {
            var window=sender as Window;
            if(window==null || window.Title!="Add running game" || window.Resources.Contains("HdrGridTheme")) return;
            // Keep the standard grid usable if a future Windows template differs.
            try {
                window.Resources["HdrGridTheme"]=true;
                window.Background=Background;window.Foreground=Text;
                window.FontFamily=new FontFamily("Segoe UI");window.FontSize=14;
                window.Width=900;window.Height=620;window.MinWidth=640;window.MinHeight=400;
                window.Resources[SystemColors.WindowBrushKey]=Surface;
                window.Resources[SystemColors.WindowTextBrushKey]=Text;
                window.Resources[SystemColors.ControlBrushKey]=Surface;
                window.Resources[SystemColors.ControlTextBrushKey]=Text;
                window.Resources[SystemColors.GrayTextBrushKey]=Muted;
                window.Resources[SystemColors.ControlDarkBrushKey]=Edge;
                window.Resources[SystemColors.ControlDarkDarkBrushKey]=Edge;
                window.Resources[SystemColors.ControlLightBrushKey]=Surface;
                window.Resources[SystemColors.ControlLightLightBrushKey]=Surface;
                window.Resources[SystemColors.HighlightBrushKey]=Brush("#314C46");
                window.Resources[SystemColors.HighlightTextBrushKey]=Text;
                window.Resources[SystemColors.InactiveSelectionHighlightBrushKey]=Brush("#314C46");
                window.Resources[SystemColors.InactiveSelectionHighlightTextBrushKey]=Text;
                var content=window.Content as UIElement;
                if(content!=null) {
                    window.Content=null;
                    var layout=new DockPanel {Margin=new Thickness(20)};
                    var header=new StackPanel {Margin=new Thickness(0,0,0,18)};
                    header.Children.Add(new TextBlock {Text="Add running game",FontSize=24,FontWeight=FontWeights.SemiBold,Foreground=Text});
                    header.Children.Add(new TextBlock {Text="Filter by name, then double-click a game or select a row and click OK.",Foreground=Muted,Margin=new Thickness(0,8,0,0),TextWrapping=TextWrapping.Wrap});
                    DockPanel.SetDock(header,Dock.Top);layout.Children.Add(header);
                    layout.Children.Add(content);window.Content=layout;
                }
                window.Dispatcher.BeginInvoke(System.Windows.Threading.DispatcherPriority.ApplicationIdle,new Action(delegate {try {Walk(window);} catch { }}));
                int dark=1;DwmSetWindowAttribute(new WindowInteropHelper(window).Handle,20,ref dark,4);
            } catch { /* Cosmetic failure must never prevent process selection. */ }
        }
        static void ControlLoaded(object sender,RoutedEventArgs args) {
            var element=sender as FrameworkElement;var window=Window.GetWindow(element);
            if(window==null || !window.Resources.Contains("HdrGridTheme")) return;
            try {StyleElement(element);} catch { }
        }
        static void Walk(DependencyObject obj) {
            var element=obj as FrameworkElement;if(element!=null) StyleElement(element);
            var border=obj as Border;
            if(border!=null && border.Name=="SearchBG") {border.Background=Background;border.Padding=new Thickness(0,0,0,12);}
            for(int i=0;i<VisualTreeHelper.GetChildrenCount(obj);i++) Walk(VisualTreeHelper.GetChild(obj,i));
        }
        static object Xaml(string body) {return XamlReader.Parse("<ResourceDictionary xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation' xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'>"+body+"</ResourceDictionary>");}
        [ThreadStatic] static ResourceDictionary styles;
        static ResourceDictionary Styles { get { return styles ?? (styles=(ResourceDictionary)Xaml(@"
            <ControlTemplate x:Key='Button' TargetType='ButtonBase'>
              <Border x:Name='Frame' Background='{TemplateBinding Background}' BorderBrush='{TemplateBinding BorderBrush}' BorderThickness='1' CornerRadius='6' Padding='{TemplateBinding Padding}'>
                <ContentPresenter HorizontalAlignment='Center' VerticalAlignment='Center' RecognizesAccessKey='True'/>
              </Border>
              <ControlTemplate.Triggers>
                <Trigger Property='IsMouseOver' Value='True'><Setter TargetName='Frame' Property='BorderBrush' Value='#89D6BE'/></Trigger>
                <Trigger Property='IsKeyboardFocused' Value='True'><Setter TargetName='Frame' Property='BorderBrush' Value='#EDF0F3'/></Trigger>
                <Trigger Property='IsPressed' Value='True'><Setter TargetName='Frame' Property='Opacity' Value='0.7'/></Trigger>
                <Trigger Property='IsEnabled' Value='False'><Setter TargetName='Frame' Property='Opacity' Value='0.4'/></Trigger>
              </ControlTemplate.Triggers>
            </ControlTemplate>
            <ControlTemplate x:Key='Scroll' TargetType='ScrollBar'>
              <Border Background='{TemplateBinding Background}'>
                <Track x:Name='PART_Track' Orientation='{TemplateBinding Orientation}' IsDirectionReversed='False'>
                  <Track.DecreaseRepeatButton><RepeatButton x:Name='PageBefore' Command='ScrollBar.PageLeftCommand' Opacity='0' Focusable='False'/></Track.DecreaseRepeatButton>
                  <Track.Thumb><Thumb><Thumb.Template><ControlTemplate TargetType='Thumb'>
                    <Border x:Name='Grip' Background='#59616C' CornerRadius='4' Margin='3'/>
                    <ControlTemplate.Triggers><Trigger Property='IsMouseOver' Value='True'><Setter TargetName='Grip' Property='Background' Value='#89D6BE'/></Trigger></ControlTemplate.Triggers>
                  </ControlTemplate></Thumb.Template></Thumb></Track.Thumb>
                  <Track.IncreaseRepeatButton><RepeatButton x:Name='PageAfter' Command='ScrollBar.PageRightCommand' Opacity='0' Focusable='False'/></Track.IncreaseRepeatButton>
                </Track>
              </Border>
              <ControlTemplate.Triggers><Trigger Property='Orientation' Value='Vertical'>
                <Setter TargetName='PART_Track' Property='IsDirectionReversed' Value='True'/>
                <Setter TargetName='PageBefore' Property='Command' Value='ScrollBar.PageUpCommand'/>
                <Setter TargetName='PageAfter' Property='Command' Value='ScrollBar.PageDownCommand'/>
              </Trigger></ControlTemplate.Triggers>
            </ControlTemplate>
            <Style x:Key='Row' TargetType='ListViewItem'>
              <Setter Property='Foreground' Value='#EDF0F3'/><Setter Property='Background' Value='Transparent'/>
              <Setter Property='MinHeight' Value='34'/><Setter Property='Padding' Value='8,5'/>
              <Setter Property='HorizontalContentAlignment' Value='Stretch'/>
              <Setter Property='Template'><Setter.Value><ControlTemplate TargetType='ListViewItem'>
                <Border x:Name='RowBorder' Background='{TemplateBinding Background}' BorderThickness='1' BorderBrush='Transparent' CornerRadius='3' Padding='{TemplateBinding Padding}'>
                  <GridViewRowPresenter Content='{TemplateBinding Content}' Columns='{Binding View.Columns, RelativeSource={RelativeSource AncestorType=ListView}}'/>
                </Border>
                <ControlTemplate.Triggers>
                  <Trigger Property='IsMouseOver' Value='True'><Setter TargetName='RowBorder' Property='Background' Value='#2B3035'/></Trigger>
                  <Trigger Property='IsSelected' Value='True'><Setter TargetName='RowBorder' Property='Background' Value='#314C46'/><Setter TargetName='RowBorder' Property='BorderBrush' Value='#89D6BE'/></Trigger>
                  <Trigger Property='IsKeyboardFocusWithin' Value='True'><Setter TargetName='RowBorder' Property='BorderBrush' Value='#89D6BE'/></Trigger>
                </ControlTemplate.Triggers>
              </ControlTemplate></Setter.Value></Setter>
            </Style>")); } }
        static void StyleElement(FrameworkElement element) {
            var text=element as TextBlock;if(text!=null && text.ReadLocalValue(TextBlock.ForegroundProperty)!=DependencyProperty.UnsetValue && text.FontSize<20 && text.Parent is ContentPresenter) text.Foreground=Text;
            var panel=element as Panel;if(panel!=null && panel.Name=="filterPanelRow") panel.Background=Background;
            var control=element as Control;if(control==null) return;
            var scroll=control as ScrollBar;if(scroll!=null) {scroll.Background=Surface;scroll.Template=(ControlTemplate)Styles["Scroll"];}
            var row=control as ListViewItem;if(row!=null) row.Style=(Style)Styles["Row"];
            var list=control as ListView;
            if(list!=null) {list.Background=Surface;list.Foreground=Text;list.BorderBrush=Edge;list.ItemContainerStyle=(Style)Styles["Row"];}
            var input=control as TextBox;
            if(input!=null) {input.Background=Surface;input.Foreground=Text;input.CaretBrush=Text;input.BorderBrush=Edge;input.Padding=new Thickness(8,6,8,6);input.MinHeight=34;}
            var header=control as GridViewColumnHeader;
            if(header!=null) {header.Background=Surface;header.Foreground=Muted;header.BorderBrush=Edge;header.Padding=new Thickness(8,9,8,9);header.MinHeight=36;}
            // Keep Microsoft's icon-only filtering controls and column templates.
            var button=control as ButtonBase;
            if(button!=null && !(button is GridViewColumnHeader) && (button.GetType()==typeof(Button) || button.Content is string || button.GetType().Name=="PopupControlButton")) {
                button.Background=Surface;button.Foreground=Text;button.BorderBrush=Edge;
                button.Template=(ControlTemplate)Styles["Button"];button.MinHeight=34;button.MinWidth=90;button.Padding=new Thickness(12,5,12,5);
                if(button is Button && ((Button)button).IsDefault) {button.Background=Accent;button.Foreground=Background;button.BorderBrush=Accent;}
            }
        }
    }
}
