#
# Ronopoly - theming.
#
# One ResourceDictionary per theme, authored as a XAML string. Only the
# surround, HUD and chrome change: the board tiles themselves are printed
# card-stock art in both themes, exactly as a real board is.
#
# Every colour is a named brush key, so no view code ever writes a literal
# colour. Switching theme re-merges the dictionary and the whole window follows.
#
# Every INPUT control is templated here too. The stock Aero2 TextBox, CheckBox
# and ComboBox are pale chrome with black text, which on a dark panel looks
# like a hole punched in the card.
#

function Get-RonThemeXaml {
    param([ValidateSet('Dark','Light')][string]$Theme = 'Dark')

    if ($Theme -eq 'Dark') {
        $c = @{
            Bg         = '#12161C'
            BgDeep     = '#0C0F14'
            Panel      = '#1B2129'
            PanelAlt   = '#232B35'
            Line       = '#2E3742'
            Text       = '#ECEFF3'
            TextDim    = '#A8B4C2'
            Accent     = '#3D8BFD'
            AccentText = '#FFFFFF'
            Good       = '#2FBF71'
            Danger     = '#F0553C'
            Felt       = '#16302A'
            Overlay    = '#C60A0D12'
        }
    }
    else {
        $c = @{
            Bg         = '#EFEBE2'
            BgDeep     = '#E2DDD2'
            Panel      = '#FFFFFF'
            PanelAlt   = '#F5F2EB'
            Line       = '#D6D0C4'
            Text       = '#1B1F26'
            TextDim    = '#5B6472'
            Accent     = '#1F6FEB'
            AccentText = '#FFFFFF'
            Good       = '#1E9E5A'
            Danger     = '#D93A2B'
            Felt       = '#CFE3D4'
            Overlay    = '#C6F3F0E9'
        }
    }

    return @"
<ResourceDictionary xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
                    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml">

  <SolidColorBrush x:Key="Brush.Bg"         Color="$($c.Bg)" />
  <SolidColorBrush x:Key="Brush.BgDeep"     Color="$($c.BgDeep)" />
  <SolidColorBrush x:Key="Brush.Panel"      Color="$($c.Panel)" />
  <SolidColorBrush x:Key="Brush.PanelAlt"   Color="$($c.PanelAlt)" />
  <SolidColorBrush x:Key="Brush.Line"       Color="$($c.Line)" />
  <SolidColorBrush x:Key="Brush.Text"       Color="$($c.Text)" />
  <SolidColorBrush x:Key="Brush.TextDim"    Color="$($c.TextDim)" />
  <SolidColorBrush x:Key="Brush.Accent"     Color="$($c.Accent)" />
  <SolidColorBrush x:Key="Brush.AccentText" Color="$($c.AccentText)" />
  <SolidColorBrush x:Key="Brush.Good"       Color="$($c.Good)" />
  <SolidColorBrush x:Key="Brush.Danger"     Color="$($c.Danger)" />
  <SolidColorBrush x:Key="Brush.Felt"       Color="$($c.Felt)" />
  <SolidColorBrush x:Key="Brush.Overlay"    Color="$($c.Overlay)" />

  <DropShadowEffect x:Key="Fx.Card" BlurRadius="18" ShadowDepth="2" Direction="270" Opacity="0.35" Color="#000000" />
  <DropShadowEffect x:Key="Fx.Lift" BlurRadius="30" ShadowDepth="8" Direction="270" Opacity="0.45" Color="#000000" />

  <Style TargetType="TextBlock">
    <Setter Property="Foreground" Value="{DynamicResource Brush.Text}" />
    <Setter Property="FontFamily" Value="Segoe UI" />
    <Setter Property="FontSize"   Value="15" />
  </Style>

  <Style x:Key="Text.Title" TargetType="TextBlock">
    <Setter Property="Foreground" Value="{DynamicResource Brush.Text}" />
    <Setter Property="FontFamily" Value="Segoe UI" />
    <Setter Property="FontSize"   Value="26" />
    <Setter Property="FontWeight" Value="SemiBold" />
  </Style>

  <Style x:Key="Text.Head" TargetType="TextBlock">
    <Setter Property="Foreground" Value="{DynamicResource Brush.TextDim}" />
    <Setter Property="FontFamily" Value="Segoe UI" />
    <Setter Property="FontSize"   Value="13" />
    <Setter Property="FontWeight" Value="SemiBold" />
  </Style>

  <Style x:Key="Text.Dim" TargetType="TextBlock">
    <Setter Property="Foreground" Value="{DynamicResource Brush.TextDim}" />
    <Setter Property="FontFamily" Value="Segoe UI" />
    <Setter Property="FontSize"   Value="14" />
  </Style>

  <Style x:Key="Card" TargetType="Border">
    <Setter Property="Background"      Value="{DynamicResource Brush.Panel}" />
    <Setter Property="BorderBrush"     Value="{DynamicResource Brush.Line}" />
    <Setter Property="BorderThickness" Value="1" />
    <Setter Property="CornerRadius"    Value="12" />
    <Setter Property="Padding"         Value="14" />
    <Setter Property="Effect"          Value="{DynamicResource Fx.Card}" />
  </Style>

  <Style TargetType="Button">
    <Setter Property="Foreground"      Value="{DynamicResource Brush.Text}" />
    <Setter Property="Background"      Value="{DynamicResource Brush.PanelAlt}" />
    <Setter Property="BorderBrush"     Value="{DynamicResource Brush.Line}" />
    <Setter Property="BorderThickness" Value="1" />
    <Setter Property="FontFamily"      Value="Segoe UI" />
    <Setter Property="FontSize"        Value="15" />
    <Setter Property="FontWeight"      Value="SemiBold" />
    <Setter Property="Padding"         Value="18,10" />
    <Setter Property="Margin"          Value="0,0,8,8" />
    <Setter Property="Cursor"          Value="Hand" />
    <Setter Property="SnapsToDevicePixels" Value="True" />
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Button">
          <Border x:Name="Chrome" CornerRadius="9"
                  Background="{TemplateBinding Background}"
                  BorderBrush="{TemplateBinding BorderBrush}"
                  BorderThickness="{TemplateBinding BorderThickness}"
                  Padding="{TemplateBinding Padding}">
            <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" />
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="Chrome" Property="BorderBrush" Value="{DynamicResource Brush.Accent}" />
            </Trigger>
            <Trigger Property="IsPressed" Value="True">
              <Setter TargetName="Chrome" Property="Opacity" Value="0.75" />
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter TargetName="Chrome" Property="Opacity" Value="0.35" />
              <Setter Property="Cursor" Value="Arrow" />
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style x:Key="Button.Primary" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
    <Setter Property="Background"  Value="{DynamicResource Brush.Accent}" />
    <Setter Property="Foreground"  Value="{DynamicResource Brush.AccentText}" />
    <Setter Property="BorderBrush" Value="{DynamicResource Brush.Accent}" />
  </Style>

  <Style x:Key="Button.Danger" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
    <Setter Property="Background"  Value="{DynamicResource Brush.Danger}" />
    <Setter Property="Foreground"  Value="#FFFFFF" />
    <Setter Property="BorderBrush" Value="{DynamicResource Brush.Danger}" />
  </Style>

  <Style x:Key="Button.Quiet" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
    <Setter Property="Background"  Value="Transparent" />
    <Setter Property="Foreground"  Value="{DynamicResource Brush.TextDim}" />
    <Setter Property="FontWeight"  Value="Normal" />
    <Setter Property="Padding"     Value="11,7" />
  </Style>

  <!-- The small button used in the dense rows of Manage property and Save. -->
  <Style x:Key="Button.Row" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
    <Setter Property="FontSize" Value="13" />
    <Setter Property="Padding"  Value="11,6" />
    <Setter Property="Margin"   Value="4,0,0,0" />
  </Style>

  <!-- The network status strip: reads as text until you point at it, then
       reads as the button it has been all along. -->
  <Style x:Key="Button.Status" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
    <Setter Property="Background"      Value="Transparent" />
    <Setter Property="Foreground"      Value="{DynamicResource Brush.TextDim}" />
    <Setter Property="BorderBrush"     Value="Transparent" />
    <Setter Property="FontSize"        Value="14" />
    <Setter Property="FontWeight"      Value="Normal" />
    <Setter Property="Padding"         Value="8,3" />
    <Setter Property="Margin"          Value="0" />
  </Style>

  <Style TargetType="TextBox">
    <Setter Property="Foreground"      Value="{DynamicResource Brush.Text}" />
    <Setter Property="Background"      Value="{DynamicResource Brush.PanelAlt}" />
    <Setter Property="CaretBrush"      Value="{DynamicResource Brush.Text}" />
    <Setter Property="SelectionBrush"  Value="{DynamicResource Brush.Accent}" />
    <Setter Property="BorderBrush"     Value="{DynamicResource Brush.Line}" />
    <Setter Property="BorderThickness" Value="1" />
    <Setter Property="FontFamily"      Value="Segoe UI" />
    <Setter Property="FontSize"        Value="15" />
    <Setter Property="Padding"         Value="9,6" />
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="TextBox">
          <Border x:Name="Chrome" CornerRadius="8"
                  Background="{TemplateBinding Background}"
                  BorderBrush="{TemplateBinding BorderBrush}"
                  BorderThickness="{TemplateBinding BorderThickness}">
            <ScrollViewer x:Name="PART_ContentHost" Margin="{TemplateBinding Padding}"
                          VerticalAlignment="Center" />
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsKeyboardFocusWithin" Value="True">
              <Setter TargetName="Chrome" Property="BorderBrush" Value="{DynamicResource Brush.Accent}" />
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter TargetName="Chrome" Property="Opacity" Value="0.4" />
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="CheckBox">
    <Setter Property="Foreground" Value="{DynamicResource Brush.Text}" />
    <Setter Property="FontFamily" Value="Segoe UI" />
    <Setter Property="FontSize"   Value="15" />
    <Setter Property="Cursor"     Value="Hand" />
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="CheckBox">
          <StackPanel Orientation="Horizontal" Background="Transparent">
            <Border x:Name="Box" Width="20" Height="20" CornerRadius="5" VerticalAlignment="Center"
                    Background="{DynamicResource Brush.PanelAlt}"
                    BorderBrush="{DynamicResource Brush.Line}" BorderThickness="1">
              <Path x:Name="Tick" Visibility="Collapsed" Stretch="Uniform" Margin="4"
                    Data="M 0,4 L 3.6,7.6 L 10,0" StrokeThickness="2"
                    Stroke="{DynamicResource Brush.AccentText}"
                    StrokeEndLineCap="Round" StrokeStartLineCap="Round" />
            </Border>
            <ContentPresenter Margin="10,0,0,0" VerticalAlignment="Center" RecognizesAccessKey="True" />
          </StackPanel>
          <ControlTemplate.Triggers>
            <Trigger Property="IsChecked" Value="True">
              <Setter TargetName="Box"  Property="Background"  Value="{DynamicResource Brush.Accent}" />
              <Setter TargetName="Box"  Property="BorderBrush" Value="{DynamicResource Brush.Accent}" />
              <Setter TargetName="Tick" Property="Visibility"  Value="Visible" />
            </Trigger>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="Box" Property="BorderBrush" Value="{DynamicResource Brush.Accent}" />
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter Property="Opacity" Value="0.4" />
              <Setter Property="Cursor"  Value="Arrow" />
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style x:Key="Combo.Toggle" TargetType="ToggleButton">
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ToggleButton">
          <Border x:Name="Chrome" CornerRadius="8"
                  Background="{DynamicResource Brush.PanelAlt}"
                  BorderBrush="{DynamicResource Brush.Line}" BorderThickness="1">
            <Path x:Name="Arrow" HorizontalAlignment="Right" VerticalAlignment="Center"
                  Margin="0,0,11,0" Data="M 0,0 L 9,0 L 4.5,5.5 Z"
                  Fill="{DynamicResource Brush.TextDim}" />
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="Chrome" Property="BorderBrush" Value="{DynamicResource Brush.Accent}" />
            </Trigger>
            <Trigger Property="IsEnabled" Value="False">
              <Setter TargetName="Chrome" Property="Opacity" Value="0.4" />
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="ComboBox">
    <Setter Property="Foreground" Value="{DynamicResource Brush.Text}" />
    <Setter Property="FontFamily" Value="Segoe UI" />
    <Setter Property="FontSize"   Value="15" />
    <Setter Property="Padding"    Value="11,7,26,7" />
    <Setter Property="Cursor"     Value="Hand" />
    <Setter Property="MinHeight"  Value="34" />
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ComboBox">
          <Grid>
            <ToggleButton Style="{StaticResource Combo.Toggle}" Focusable="False" ClickMode="Press"
                          IsChecked="{Binding IsDropDownOpen, Mode=TwoWay, RelativeSource={RelativeSource TemplatedParent}}" />
            <ContentPresenter Margin="{TemplateBinding Padding}" IsHitTestVisible="False"
                              HorizontalAlignment="Left" VerticalAlignment="Center"
                              Content="{TemplateBinding SelectionBoxItem}"
                              ContentTemplate="{TemplateBinding SelectionBoxItemTemplate}" />
            <Popup x:Name="PART_Popup" Placement="Bottom" AllowsTransparency="True" Focusable="False"
                   IsOpen="{TemplateBinding IsDropDownOpen}" PopupAnimation="Fade">
              <Border Margin="0,4,0,0" CornerRadius="8" BorderThickness="1"
                      Background="{DynamicResource Brush.Panel}"
                      BorderBrush="{DynamicResource Brush.Line}"
                      Effect="{DynamicResource Fx.Card}"
                      MaxHeight="{TemplateBinding MaxDropDownHeight}"
                      MinWidth="{Binding ActualWidth, RelativeSource={RelativeSource TemplatedParent}}">
                <ScrollViewer>
                  <ItemsPresenter />
                </ScrollViewer>
              </Border>
            </Popup>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="IsEnabled" Value="False">
              <Setter Property="Opacity" Value="0.45" />
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="ComboBoxItem">
    <Setter Property="Foreground" Value="{DynamicResource Brush.Text}" />
    <Setter Property="FontFamily" Value="Segoe UI" />
    <Setter Property="FontSize"   Value="15" />
    <Setter Property="Padding"    Value="11,8" />
    <Setter Property="Cursor"     Value="Hand" />
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ComboBoxItem">
          <Border x:Name="Chrome" Background="Transparent" CornerRadius="5"
                  Padding="{TemplateBinding Padding}">
            <ContentPresenter />
          </Border>
          <ControlTemplate.Triggers>
            <Trigger Property="IsHighlighted" Value="True">
              <Setter TargetName="Chrome" Property="Background" Value="{DynamicResource Brush.Accent}" />
              <Setter Property="Foreground" Value="{DynamicResource Brush.AccentText}" />
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <!-- The stock scrollbar is a pale Windows 8 slab, and it is the one piece of
       chrome left that gives away that this is a dark theme painted over a
       light toolkit. -->
  <Style x:Key="Scroll.Thumb" TargetType="Thumb">
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="Thumb">
          <Border x:Name="Bar" CornerRadius="4" Margin="3,2"
                  Background="{DynamicResource Brush.Line}" />
          <ControlTemplate.Triggers>
            <Trigger Property="IsMouseOver" Value="True">
              <Setter TargetName="Bar" Property="Background" Value="{DynamicResource Brush.TextDim}" />
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>

  <Style TargetType="ScrollBar">
    <Setter Property="Width" Value="12" />
    <Setter Property="Background" Value="Transparent" />
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ScrollBar">
          <Grid Background="Transparent">
            <Track x:Name="PART_Track" IsDirectionReversed="True"
                   Orientation="{TemplateBinding Orientation}">
              <Track.DecreaseRepeatButton>
                <RepeatButton Command="ScrollBar.PageUpCommand" Opacity="0" Focusable="False" />
              </Track.DecreaseRepeatButton>
              <Track.Thumb>
                <Thumb Style="{StaticResource Scroll.Thumb}" />
              </Track.Thumb>
              <Track.IncreaseRepeatButton>
                <RepeatButton Command="ScrollBar.PageDownCommand" Opacity="0" Focusable="False" />
              </Track.IncreaseRepeatButton>
            </Track>
          </Grid>
          <ControlTemplate.Triggers>
            <Trigger Property="Orientation" Value="Horizontal">
              <Setter TargetName="PART_Track" Property="IsDirectionReversed" Value="False" />
            </Trigger>
          </ControlTemplate.Triggers>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
    <Style.Triggers>
      <Trigger Property="Orientation" Value="Horizontal">
        <Setter Property="Width" Value="Auto" />
        <Setter Property="Height" Value="12" />
      </Trigger>
    </Style.Triggers>
  </Style>

  <Style TargetType="ToolTip">
    <Setter Property="Foreground" Value="{DynamicResource Brush.Text}" />
    <Setter Property="FontFamily" Value="Segoe UI" />
    <Setter Property="FontSize"   Value="14" />
    <Setter Property="Template">
      <Setter.Value>
        <ControlTemplate TargetType="ToolTip">
          <Border CornerRadius="7" Padding="10,7" BorderThickness="1"
                  Background="{DynamicResource Brush.Panel}"
                  BorderBrush="{DynamicResource Brush.Line}">
            <ContentPresenter />
          </Border>
        </ControlTemplate>
      </Setter.Value>
    </Setter>
  </Style>
</ResourceDictionary>
"@
}

function Set-RonTheme {
    param(
        [Parameter(Mandatory)][System.Windows.Window]$Window,
        [ValidateSet('Dark','Light')][string]$Theme = 'Dark'
    )
    $dict = ConvertFrom-RonXaml (Get-RonThemeXaml -Theme $Theme)
    $Window.Resources.MergedDictionaries.Clear()
    [void]$Window.Resources.MergedDictionaries.Add($dict)

    # The safety net, and it is not decoration.
    #
    # WPF resolves an element's IMPLICIT style when it is added to its parent.
    # Every overlay in this app builds its subtree detached and attaches the
    # finished card at the end, so that lookup runs while the subtree can still
    # see no resources at all - and the answer is never revisited. The TextBlock
    # style above was therefore skipped for every label in every panel, leaving
    # them at the WPF default: BLACK text, on a dark grey card. That is exactly
    # what the auction and trade screens showed.
    #
    # Foreground, FontFamily and FontSize are INHERITED properties, and
    # inheritance IS re-evaluated when the tree changes. Setting them on the
    # window makes the readable value the default that flows down to whatever
    # the styles miss, whenever it is finally attached. Controls carrying their
    # own themed foreground - buttons, the input controls above - still
    # override it in the usual way.
    $Window.Foreground = $dict['Brush.Text']
    $Window.FontFamily = New-Object System.Windows.Media.FontFamily 'Segoe UI'
    $Window.FontSize   = 15
    return $Theme
}

# XamlReader.Load over an XmlReader rather than ::Parse, which avoids the
# encoding guesswork ::Parse does on a raw string.
#
# NOTE: XamlReader cannot handle x:Class or event attributes (Click="..."), so
# every XAML string in this project is structure-only and all handlers are
# attached in code after FindName.
function ConvertFrom-RonXaml {
    param([Parameter(Mandatory)][string]$Xaml)
    $reader = [System.Xml.XmlReader]::Create((New-Object System.IO.StringReader $Xaml))
    try { return [Windows.Markup.XamlReader]::Load($reader) }
    finally { $reader.Close() }
}
