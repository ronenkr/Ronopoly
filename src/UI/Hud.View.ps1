#
# Ronopoly - the side panel: player cards, the action buttons and the log.
#
# Player cards are built once and updated in place, for the same reason the
# board tiles are: rebuilding a panel every turn churns the visual tree and
# re-registers handlers.
#

function Initialize-RonHudView {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][GameState]$State
    )
    $list = $Ui.PlayerList
    $list.Children.Clear()
    $cards = @{}

    foreach ($id in $State.Order) {
        $p = $State.Players[$id]
        $card = New-RonPlayerCard -State $State -PlayerId $id
        [void]$list.Children.Add($card.Root)
        $cards[$id] = $card
    }
    $Ui.PlayerCards = $cards
    $Ui.LogLines = New-Object System.Collections.ArrayList
    return $cards
}

function New-RonPlayerCard {
    param([Parameter(Mandatory)][GameState]$State, [Parameter(Mandatory)][int]$PlayerId)
    $p = $State.Players[$PlayerId]
    $colour = Get-RonPlayerColour -State $State -PlayerId $PlayerId

    $root = New-Object System.Windows.Controls.Border
    $root.CornerRadius = New-Object System.Windows.CornerRadius 8
    $root.Padding = New-Object System.Windows.Thickness(10, 8, 10, 8)
    $root.Margin = New-Object System.Windows.Thickness(0, 0, 0, 6)
    $root.BorderThickness = New-Object System.Windows.Thickness(3, 0, 0, 0)
    $root.BorderBrush = New-RonBrush $colour

    $grid = New-Object System.Windows.Controls.Grid
    foreach ($w in @('Auto', '*', 'Auto')) {
        $cd = New-Object System.Windows.Controls.ColumnDefinition
        if ($w -eq 'Auto') { $cd.Width = [System.Windows.GridLength]::Auto }
        else { $cd.Width = New-Object System.Windows.GridLength(1, [System.Windows.GridUnitType]::Star) }
        $grid.ColumnDefinitions.Add($cd)
    }

    $token = New-Object System.Windows.Controls.Image
    $token.Source = Get-RonTokenImage $p.Token
    $token.Width = 34
    $token.Height = 34
    $token.Margin = New-Object System.Windows.Thickness(0, 0, 10, 0)
    [System.Windows.Media.RenderOptions]::SetBitmapScalingMode($token, [System.Windows.Media.BitmapScalingMode]::HighQuality)
    [System.Windows.Controls.Grid]::SetColumn($token, 0)
    [void]$grid.Children.Add($token)

    $middle = New-Object System.Windows.Controls.StackPanel
    [System.Windows.Controls.Grid]::SetColumn($middle, 1)
    $name = New-Object System.Windows.Controls.TextBlock
    $name.FontWeight = [System.Windows.FontWeights]::SemiBold
    $name.Text = $p.Name
    [void]$middle.Children.Add($name)
    $detail = New-Object System.Windows.Controls.TextBlock
    $detail.FontSize = 13
    $detail.Opacity = 0.7
    [void]$middle.Children.Add($detail)
    [void]$grid.Children.Add($middle)

    $cash = New-Object System.Windows.Controls.TextBlock
    $cash.FontSize = 17
    $cash.FontWeight = [System.Windows.FontWeights]::SemiBold
    $cash.VerticalAlignment = [System.Windows.VerticalAlignment]::Center
    [System.Windows.Controls.Grid]::SetColumn($cash, 2)
    [void]$grid.Children.Add($cash)

    $root.Child = $grid
    return @{ Root = $root; Name = $name; Detail = $detail; Cash = $cash; Token = $token }
}

function Update-RonHudView {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][GameState]$State
    )
    $acting = Get-RonActingPlayerId -State $State

    foreach ($id in $State.Order) {
        $card = $Ui.PlayerCards[$id]
        if ($null -eq $card) { continue }
        $p = $State.Players[$id]

        $card.Cash.Text = Format-RonMoney $p.Cash
        $owned = @(Get-RonOwnedIndices -State $State -PlayerId $id).Count
        $b = Get-RonBuildingCount -State $State -PlayerId $id

        $bits = New-Object System.Collections.ArrayList
        [void]$bits.Add("$owned deeds")
        if ($b.Houses -gt 0) { [void]$bits.Add("$($b.Houses) houses") }
        if ($b.Hotels -gt 0) { [void]$bits.Add("$($b.Hotels) hotels") }
        if ($p.JailCards -gt 0) { [void]$bits.Add("$($p.JailCards) jail card") }
        if ($p.Kind -eq 'AI') { [void]$bits.Add($p.AiProfile) }
        if ($p.InJail) { [void]$bits.Add('IN JAIL') }
        if ($p.ConnectionState -eq 'Disconnected') { [void]$bits.Add('disconnected') }
        if ($p.ConnectionState -eq 'AiTakeover')   { [void]$bits.Add('AI takeover') }
        $card.Detail.Text = ($bits.ToArray() -join '  -  ')

        if ($p.IsBankrupt) {
            $card.Root.Opacity = 0.35
            $card.Root.Background = $null
            $card.Detail.Text = 'bankrupt'
        }
        elseif ($id -eq $acting) {
            $card.Root.Opacity = 1.0
            $card.Root.Background = $Ui.Window.FindResource('Brush.PanelAlt')
        }
        else {
            $card.Root.Opacity = 0.82
            $card.Root.Background = $null
        }
    }

    $bank = "Bank: $($State.Bank.HousesAvailable) houses, $($State.Bank.HotelsAvailable) hotels"
    if ($State.RuleOn('FreeParkingJackpot')) {
        $bank += "   Pot: " + (Format-RonMoney $State.Bank.FreeParkingPot)
    }
    $Ui.BankText.Text = $bank

    $Ui.TurnText.Text = "Turn $($State.Turn.TurnNumber) - $($State.Players[$acting].Name)"
    $phaseKey = 'Phase.' + $State.Turn.Phase
    $Ui.PhaseText.Text = Get-RonString $phaseKey
}

# --- game log --------------------------------------------------------------

function Add-RonLogLine {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][string]$Text,
        [string]$Colour = ''
    )
    if ([string]::IsNullOrWhiteSpace($Text)) { return }

    $line = New-Object System.Windows.Controls.TextBlock
    $line.Text = $Text
    $line.TextWrapping = [System.Windows.TextWrapping]::Wrap
    $line.Margin = New-Object System.Windows.Thickness(0, 0, 0, 4)
    $line.FontSize = 13
    if ($Colour) { $line.Foreground = New-RonBrush $Colour }
    else { $line.Opacity = 0.85 }

    [void]$Ui.LogList.Items.Add($line)

    # A game can run 800 turns; an unbounded log would grow the visual tree
    # without limit for text nobody scrolls back to.
    while ($Ui.LogList.Items.Count -gt 300) { $Ui.LogList.Items.RemoveAt(0) }
    $Ui.LogScroll.ScrollToEnd()
}

function Add-RonEventLog {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][object[]]$Events
    )
    foreach ($e in $Events) {
        $text = Format-RonEvent -State $State -Event $e
        if (-not $text) { continue }
        $colour = ''
        if ($e.T -eq 'Bankrupt')  { $colour = '#F0553C' }
        if ($e.T -eq 'GameOver')  { $colour = '#2FBF71' }
        if ($e.T -eq 'CardDrawn') { $colour = '#E8930C' }
        Add-RonLogLine -Ui $Ui -Text $text -Colour $colour
    }
}

# --- action buttons --------------------------------------------------------
#
# Rebuilt each time the legal set changes, which is unavoidable: the set of
# buttons IS the set of legal actions. Handlers close over the action object
# and hand it to the App's queue rather than calling the engine directly.

function Update-RonActionPanel {
    param(
        [Parameter(Mandatory)][hashtable]$Ui,
        [Parameter(Mandatory)][GameState]$State,
        [Parameter(Mandatory)][scriptblock]$OnAction,
        [bool]$Enabled = $true
    )
    $panel = $Ui.ActionPanel
    $panel.Children.Clear()

    if ($State.IsOver) {
        $Ui.PromptText.Text = ''
        return
    }

    $acting = Get-RonActingPlayerId -State $State
    $player = $State.Players[$acting]

    if ($player.IsAiControlled()) {
        $Ui.PromptText.Text = "$($player.Name) is thinking..."
        return
    }
    if (-not $Enabled) {
        $Ui.PromptText.Text = 'Resolving...'
        return
    }

    $Ui.PromptText.Text = Get-RonActionPrompt -State $State
    foreach ($action in (Get-RonPrimaryActions -State $State)) {
        $btn = New-Object System.Windows.Controls.Button
        $btn.Content = $action.Label
        if ($action.Style) { $btn.Style = $Ui.Window.FindResource($action.Style) }
        if ($action.ContainsKey('Enabled')) { $btn.IsEnabled = [bool]$action.Enabled }
        if ($action.ContainsKey('Note') -and $action.Note) { $btn.ToolTip = $action.Note }
        $captured = $action.Action
        if ($null -ne $captured) {
            $btn.Add_Click({ & $OnAction $captured }.GetNewClosure())
        }
        [void]$panel.Children.Add($btn)
    }

    # Managing property and trading open their own panels rather than putting
    # one button per deed here - a late-game turn would otherwise produce
    # twenty buttons in a 380-pixel column.
    if ($script:RonManagementPhases -contains $State.Turn.Phase) {
        $manage = New-Object System.Windows.Controls.Button
        $manage.Content = 'Manage property'
        $manage.Add_Click({ Show-RonManageOverlay })
        [void]$panel.Children.Add($manage)

        if ($State.Turn.Phase -ne 'AwaitDebt' -or $State.ActivePlayers().Count -gt 1) {
            $trade = New-Object System.Windows.Controls.Button
            $trade.Content = 'Trade'
            $trade.Add_Click({ Show-RonTradeOverlay })
            [void]$panel.Children.Add($trade)
        }
    }
}

function Get-RonActionPrompt {
    param([Parameter(Mandatory)][GameState]$State)
    switch ($State.Turn.Phase) {
        'AwaitBuyDecision' {
            $i = $State.Turn.PendingSpaceIndex
            $price = Get-RonSpacePrice $i
            $cash = $State.Players[(Get-RonActingPlayerId -State $State)].Cash
            if ($cash -lt $price) {
                return ('{0} costs {1} and you hold {2}. Mortgage or sell to raise the rest, or send it to auction.' -f
                    (Get-RonSpaceName $i), (Format-RonMoney $price), (Format-RonMoney $cash))
            }
            return ('{0} is unowned. Buy it for {1}, or send it to auction.' -f (Get-RonSpaceName $i), (Format-RonMoney $price))
        }
        'AwaitAuction' {
            $a = $State.Turn.Auction
            $lead = 'no bids yet'
            if ($a.HighBidderId -ge 0) { $lead = "$($State.Players[$a.HighBidderId].Name) leads with $(Format-RonMoney $a.CurrentBid)" }
            return ('{0} under the hammer - {1}.' -f (Get-RonSpaceName $a.SpaceIndex), $lead)
        }
        'AwaitDebt' {
            $d = $State.Turn.Debt
            $to = 'the bank'
            if ($d.CreditorId -ge 0) { $to = $State.Players[$d.CreditorId].Name }
            return ('You owe {0} {1}. Raise it, or declare bankruptcy.' -f $to, (Format-RonMoney $d.Amount))
        }
        'AwaitJailChoice' {
            $fine = [int](Get-RonBoard).JailFine
            if ($State.Players[(Get-RonActingPlayerId -State $State)].Cash -lt $fine) {
                return ('You are in jail and cannot cover the {0} fine. Raise it, use a card, or roll for doubles.' -f (Format-RonMoney $fine))
            }
            return 'You are in jail. Pay the fine, use a card, or roll for doubles.'
        }
        'AwaitTradeResponse' { return 'A trade has been offered to you.' }
        'AwaitRoll'  { return 'Roll the dice, or manage your property first.' }
        'AwaitEndTurn' { return 'Build, trade or mortgage, then end your turn.' }
    }
    return ''
}

# The buttons that always belong on the panel. Property management gets its own
# overlay rather than one button per deed, which would produce twenty buttons
# in a late-game turn.
function Get-RonPrimaryActions {
    param([Parameter(Mandatory)][GameState]$State)
    $out = New-Object System.Collections.ArrayList
    $acting = Get-RonActingPlayerId -State $State
    $legal = @(Get-RonLegalActions -State $State -PlayerId $acting)
    $has = { param($kind) foreach ($a in $legal) { if ($a.Kind -eq $kind) { return $a } } ; return $null }

    $roll = & $has 'Roll'
    if ($roll) { [void]$out.Add(@{ Label = 'Roll dice'; Action = $roll; Style = 'Button.Primary' }) }

    $jailRoll = & $has 'JailRoll'
    if ($jailRoll) { [void]$out.Add(@{ Label = 'Roll for doubles'; Action = $jailRoll; Style = 'Button.Primary' }) }
    $fine = & $has 'PayJailFine'
    if ($fine) { [void]$out.Add(@{ Label = ('Pay ' + (Format-RonMoney $fine.Amount)); Action = $fine; Style = '' }) }
    elseif ($State.Turn.Phase -eq 'AwaitJailChoice') {
        # Same treatment as the Buy button: the fine is not unavailable, it is
        # unaffordable, and mortgaging is legal from right here.
        $amount = [int](Get-RonBoard).JailFine
        [void]$out.Add(@{
            Label   = ('Pay ' + (Format-RonMoney $amount))
            Action  = $null
            Style   = ''
            Enabled = $false
            Note    = ((Format-RonMoney ($amount - $State.Players[$acting].Cash)) + ' short - mortgage or sell something to cover it')
        })
    }
    $card = & $has 'UseJailCard'
    if ($card) { [void]$out.Add(@{ Label = 'Use jail card'; Action = $card; Style = '' }) }

    $buy = & $has 'BuyProperty'
    if ($buy) { [void]$out.Add(@{ Label = ('Buy for ' + (Format-RonMoney $buy.Amount)); Action = $buy; Style = 'Button.Primary' }) }
    elseif ($State.Turn.Phase -eq 'AwaitBuyDecision') {
        # Short of the price. Show the button anyway, greyed out with the sum
        # missing on it: "no Buy button" reads as "you may not buy this", when
        # the truth is "you may, once you have raised another 40 pounds".
        $price = Get-RonSpacePrice $State.Turn.PendingSpaceIndex
        $short = $price - $State.Players[$acting].Cash
        [void]$out.Add(@{
            Label   = ('Buy for ' + (Format-RonMoney $price))
            Action  = $null
            Style   = 'Button.Primary'
            Enabled = $false
            Note    = ((Format-RonMoney $short) + ' short - mortgage or sell something to cover it')
        })
    }
    $decline = & $has 'DeclineProperty'
    if ($decline) {
        $label = 'Send to auction'
        if ($State.RuleOn('DisableAuctions')) { $label = 'Leave it' }
        [void]$out.Add(@{ Label = $label; Action = $decline; Style = '' })
    }

    $bankrupt = & $has 'DeclareBankruptcy'
    if ($bankrupt) { [void]$out.Add(@{ Label = 'Declare bankruptcy'; Action = $bankrupt; Style = 'Button.Danger' }) }

    $end = & $has 'EndTurn'
    if ($end) { [void]$out.Add(@{ Label = 'End turn'; Action = $end; Style = 'Button.Primary' }) }

    return $out.ToArray()
}
