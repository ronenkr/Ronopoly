#
# Ronopoly - the main window layout.
#
# Structure-only XAML: XamlReader rejects x:Class and event attributes, so
# every handler is wired in code after FindName (see App.ps1).
#
# The board lives inside a Viewbox at a fixed logical size, which is the single
# line that makes every resize, aspect ratio and DPI case work: the board is
# authored once at 1224x1224 units and scaled uniformly to whatever space is
# left over.
#
# Overlays are LAYERS in this window, not separate windows. ShowDialog would
# pump a nested dispatcher loop that fights the turn state machine and behaves
# differently for a local player than a remote one.
#

function Get-RonMainWindowXaml {
    return @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Ronopoly" Width="1560" Height="1010" MinWidth="1180" MinHeight="760"
        WindowStartupLocation="CenterScreen"
        Background="{DynamicResource Brush.Bg}"
        UseLayoutRounding="True" TextOptions.TextFormattingMode="Ideal">

  <Grid x:Name="RootGrid">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto" />
      <RowDefinition Height="*" />
    </Grid.RowDefinitions>

    <!-- title strip -->
    <Border Grid.Row="0" Background="{DynamicResource Brush.BgDeep}" Padding="18,10"
            BorderBrush="{DynamicResource Brush.Line}" BorderThickness="0,0,0,1">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto" />
          <ColumnDefinition Width="*" />
          <ColumnDefinition Width="Auto" />
        </Grid.ColumnDefinitions>

        <StackPanel Grid.Column="0" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="RONOPOLY" FontSize="22" FontWeight="Bold" Foreground="{DynamicResource Brush.Accent}" />
          <TextBlock Text="London" Margin="10,0,0,0" VerticalAlignment="Center" Style="{DynamicResource Text.Dim}" />
        </StackPanel>

        <StackPanel Grid.Column="1" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center">
          <TextBlock x:Name="TurnText"  Text="" FontWeight="SemiBold" />
          <TextBlock Text="  -  " Style="{DynamicResource Text.Dim}" />
          <TextBlock x:Name="PhaseText" Text="" Style="{DynamicResource Text.Dim}" />
        </StackPanel>

        <StackPanel Grid.Column="2" Orientation="Horizontal">
          <Button x:Name="BtnSave"   Content="Save / load" Style="{DynamicResource Button.Quiet}" Margin="0" />
          <Button x:Name="BtnRules"  Content="House rules" Style="{DynamicResource Button.Quiet}" Margin="6,0,0,0" />
          <Button x:Name="BtnSound"  Content="Sound"       Style="{DynamicResource Button.Quiet}" Margin="6,0,0,0" />
          <Button x:Name="BtnTheme"  Content="Theme"       Style="{DynamicResource Button.Quiet}" Margin="6,0,0,0" />
          <Button x:Name="BtnNewGame" Content="New game"   Style="{DynamicResource Button.Quiet}" Margin="6,0,0,0" />
        </StackPanel>
      </Grid>
    </Border>

    <!-- board + side panel -->
    <Grid Grid.Row="1" Margin="16">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*" />
        <ColumnDefinition Width="Auto" />
      </Grid.ColumnDefinitions>

      <Viewbox Grid.Column="0" Stretch="Uniform" HorizontalAlignment="Stretch" VerticalAlignment="Stretch">
        <!-- Fixed logical canvas. Everything inside is authored in these units
             and never has to know the window size. -->
        <Grid x:Name="BoardRoot" Width="1224" Height="1224">
          <Border Background="{DynamicResource Brush.Felt}" CornerRadius="6" />
          <Grid x:Name="BoardGrid" />
          <Canvas x:Name="OrnamentCanvas" IsHitTestVisible="False" />
          <Canvas x:Name="TokenCanvas"    IsHitTestVisible="False" />
        </Grid>
      </Viewbox>

      <Grid Grid.Column="1" Width="430" Margin="16,0,0,0">
        <Grid.RowDefinitions>
          <RowDefinition Height="Auto" />
          <RowDefinition Height="Auto" />
          <RowDefinition Height="*" />
          <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>

        <!-- dice + what to do next -->
        <Border Grid.Row="0" Style="{DynamicResource Card}" Margin="0,0,0,12">
          <StackPanel>
            <TextBlock Text="THIS TURN" Style="{DynamicResource Text.Head}" Margin="0,0,0,10" />
            <StackPanel x:Name="DiceHost" Orientation="Horizontal" Height="80" Margin="0,0,0,10" />
            <TextBlock x:Name="PromptText" TextWrapping="Wrap" Style="{DynamicResource Text.Dim}" Margin="0,0,0,10" />
            <WrapPanel x:Name="ActionPanel" />
          </StackPanel>
        </Border>

        <!-- players -->
        <Border Grid.Row="1" Style="{DynamicResource Card}" Margin="0,0,0,12">
          <StackPanel>
            <TextBlock Text="PLAYERS" Style="{DynamicResource Text.Head}" Margin="0,0,0,10" />
            <StackPanel x:Name="PlayerList" />
          </StackPanel>
        </Border>

        <!-- log -->
        <Border Grid.Row="2" Style="{DynamicResource Card}">
          <Grid>
            <Grid.RowDefinitions>
              <RowDefinition Height="Auto" />
              <RowDefinition Height="*" />
            </Grid.RowDefinitions>
            <TextBlock Grid.Row="0" Text="GAME LOG" Style="{DynamicResource Text.Head}" Margin="0,0,0,8" />
            <ScrollViewer x:Name="LogScroll" Grid.Row="1" VerticalScrollBarVisibility="Auto"
                          HorizontalScrollBarVisibility="Disabled">
              <ItemsControl x:Name="LogList" />
            </ScrollViewer>
          </Grid>
        </Border>

        <Border Grid.Row="3" Style="{DynamicResource Card}" Margin="0,12,0,0" Padding="14,10">
          <Grid>
            <Grid.ColumnDefinitions>
              <ColumnDefinition Width="*" />
              <ColumnDefinition Width="Auto" />
            </Grid.ColumnDefinitions>
            <TextBlock Grid.Column="0" x:Name="BankText" Style="{DynamicResource Text.Dim}" />
            <TextBlock Grid.Column="1" x:Name="NetText"  Style="{DynamicResource Text.Dim}" />
          </Grid>
        </Border>
      </Grid>
    </Grid>

    <!-- overlay layer: one dispatcher loop, one code path, local or remote -->
    <Grid x:Name="OverlayLayer" Grid.RowSpan="2" Visibility="Collapsed">
      <Border x:Name="OverlayScrim" Background="{DynamicResource Brush.Overlay}" />
      <ContentControl x:Name="OverlayHost" HorizontalAlignment="Center" VerticalAlignment="Center" />
    </Grid>

    <!-- transient banner for card reveals and big moments -->
    <Grid x:Name="ToastLayer" Grid.RowSpan="2" IsHitTestVisible="False" VerticalAlignment="Top" Margin="0,80,0,0">
      <ContentControl x:Name="ToastHost" HorizontalAlignment="Center" />
    </Grid>
  </Grid>
</Window>
"@
}
