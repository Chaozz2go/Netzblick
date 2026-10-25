function Initialize-Updates {
    $script:updateJob=$null;$script:updateRelease=$null
    $ui.InstalledVersion.Text='Installiert: '+[Netzblick.ReleaseUpdates]::CurrentVersion+' · Build '+[Netzblick.ReleaseUpdates]::CurrentBuild
    $ui.TokenStatus.Text=if([Netzblick.UpdateCredentials]::Exists){'Optionaler Zugang gespeichert; öffentliche Updates werden ohne Token geprüft.'}else{'Öffentliche Updates sind ohne GitHub-Anmeldung und ohne Token verfügbar.'}
    $ui.CheckUpdates.Add_Click({
        if($script:updateJob){return};$ui.CheckUpdates.IsEnabled=$false;$ui.OpenUpdate.IsEnabled=$false;$ui.UpdateMessage.Text='GitHub wird geprüft …';$ui.UpdateNotes.Text='';$ui.ReleaseKind.Text=''
        $script:updateJob=[Netzblick.ReleaseUpdates]::Start([bool]$ui.IncludeDrafts.IsChecked,[bool]$ui.IncludePrereleases.IsChecked)
    })
    $ui.OpenReleases.Add_Click({Start-Process 'https://github.com/Chaozz2go/Netzblick/releases'})
    $ui.OpenUpdate.Add_Click({if($script:updateRelease -and [Netzblick.ReleaseUpdates]::SafeReleaseUrl($updateRelease.Url)){Start-Process $updateRelease.Url}})
    $ui.SaveGitHubToken.Add_Click({try{[Netzblick.UpdateCredentials]::Save($ui.GitHubToken.Password);$ui.GitHubToken.Clear();$ui.TokenStatus.Text='Zugang verschlüsselt gespeichert. Jetzt auf Updates prüfen.'}catch{$ui.GitHubToken.Clear();$ui.TokenStatus.Text=$_.Exception.GetBaseException().Message}})
    $ui.ForgetGitHubToken.Add_Click({try{[Netzblick.UpdateCredentials]::Forget();$ui.GitHubToken.Clear();$ui.TokenStatus.Text='Gespeicherter Zugang entfernt.'}catch{$ui.TokenStatus.Text='Zugang konnte nicht entfernt werden.'}})
    $script:updateTimer=New-Object Windows.Threading.DispatcherTimer;$updateTimer.Interval=[timespan]::FromMilliseconds(300)
    $updateTimer.Add_Tick({
        if($script:updateJob -and $updateJob.IsCompleted){
            try{$result=$updateJob.GetAwaiter().GetResult();$script:updateRelease=$result.Release;$ui.UpdateMessage.Text=$result.Message;$ui.OpenUpdate.IsEnabled=[bool]($result.Release -and [Netzblick.ReleaseUpdates]::SafeReleaseUrl($result.Release.Url));if($result.Release){$ui.UpdateNotes.Text=$result.Release.Notes;$ui.ReleaseKind.Text=if($result.Release.Draft){'Entwurf · Entwicklungsversion'}elseif($result.Release.Prerelease){'Testversion'}else{'Veröffentlichte Version'}}}catch{$ui.UpdateMessage.Text='Updateprüfung fehlgeschlagen. Bitte erneut versuchen.'}finally{$script:updateJob=$null;$ui.CheckUpdates.IsEnabled=$true}
        }
    });$updateTimer.Start();$window.Add_Closed({$updateTimer.Stop()})
}
