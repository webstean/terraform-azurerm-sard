## PowerShell
## GitHub Cli (GH) needs to be installed

if (-not (Get-Command gh -ErrorAction SilentlyContinue)) {
   throw 'GitHub CLI (gh) not found. Install via: winget install GitHub.cli'
}
if (-not (gh auth status 2>&1 | Select-String 'Logged in')) {
    throw 'Not authenticated. Run: gh auth login'
}
if (-not $Owner) {
    $Owner = (gh api user | ConvertFrom-Json).login
}
Write-Host "Repository owner is: '$Owner'"

Write-Host "Creating repo $owner/$repoName"
if (gh repo view ${Owner}/${repoName} 2>$null) {
    throw 'Repository directory already exists.'
}
if (-not (gh repo create $Owner/$repoName --description "$Description" --private )) {
    throw 'Failed to create repository.'
}

# Final script output for automation/consumers
Write-Output ([pscustomobject]@{
    Repo       = "https://github.com/$Owner/$repoName"
    RepoOwner  = $Owner
    RepoName   = $repoName
    ModuleName = $ModuleName
})


