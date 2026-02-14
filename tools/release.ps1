param(
	[Parameter(Mandatory = $true)]
	[string]$Version,
	[switch]$Push,
	[switch]$ForceTag
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
	Write-Error $Message
	exit 1
}

function RunGit([string[]]$GitArgs) {
	$cmd = "git " + ($GitArgs -join " ")
	Write-Host ">> $cmd"
	& git @GitArgs
	if ($LASTEXITCODE -ne 0) {
		Fail "Git command failed: $cmd"
	}
}

if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
	Fail "git is not available in PATH."
}

if ($Version -notmatch '^\d+\.\d+\.\d+$') {
	Fail "Version must match SemVer format X.Y.Z (example: 1.3.19)."
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = Resolve-Path (Join-Path $scriptDir "..")
Set-Location $repoRoot

RunGit "rev-parse", "--show-toplevel" | Out-Null

$tocPath = Join-Path $repoRoot "GMS/GMS.toc"
$changelogPath = Join-Path $repoRoot "GMS/Core/Changelog.lua"

if (-not (Test-Path $tocPath)) {
	Fail "Missing TOC file: $tocPath"
}
if (-not (Test-Path $changelogPath)) {
	Fail "Missing changelog file: $changelogPath"
}

$tocText = Get-Content $tocPath -Raw
$tocMatch = [regex]::Match($tocText, '(?m)^## Version:\s*([0-9]+\.[0-9]+\.[0-9]+)\s*$')
if (-not $tocMatch.Success) {
	Fail "Could not parse TOC version from GMS/GMS.toc"
}
$tocVersion = $tocMatch.Groups[1].Value

$changelogText = Get-Content $changelogPath -Raw
$releasesBlockMatch = [regex]::Match($changelogText, '(?s)local\s+RELEASES\s*=\s*\{(.*?)\n\}')
if (-not $releasesBlockMatch.Success) {
	Fail "Could not parse RELEASES block from GMS/Core/Changelog.lua"
}
$releasesBlock = $releasesBlockMatch.Groups[1].Value
$releaseVersionMatch = [regex]::Match($releasesBlock, 'version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"')
if (-not $releaseVersionMatch.Success) {
	Fail "Could not parse latest release version from RELEASES block"
}
$latestReleaseVersion = $releaseVersionMatch.Groups[1].Value

if ($tocVersion -ne $Version) {
	Fail "TOC version ($tocVersion) does not match requested release version ($Version)."
}
if ($latestReleaseVersion -ne $Version) {
	Fail "Latest changelog release version ($latestReleaseVersion) does not match requested release version ($Version)."
}

$status = (& git status --porcelain=v1)
if ($LASTEXITCODE -ne 0) {
	Fail "Failed to read git status."
}
if ($status) {
	Fail "Working tree is not clean. Commit or stash changes before creating a release tag."
}

$tag = "v$Version"
$tagExists = $false
& git rev-parse --verify --quiet "refs/tags/$tag" | Out-Null
if ($LASTEXITCODE -eq 0) {
	$tagExists = $true
}

if ($tagExists -and -not $ForceTag) {
	Fail "Tag $tag already exists. Use -ForceTag to move it."
}

if ($tagExists -and $ForceTag) {
	RunGit "tag", "-f", $tag, "-m", "Release $tag"
} else {
	RunGit "tag", "-a", $tag, "-m", "Release $tag"
}

if ($Push) {
	RunGit "push"
	RunGit "push", "--tags"
}

Write-Host ""
Write-Host "Release tag created: $tag" -ForegroundColor Green
if ($Push) {
	Write-Host "Pushed branch and tags to remote." -ForegroundColor Green
} else {
	Write-Host "Tag is local only. Use 'git push --tags' to publish." -ForegroundColor Yellow
}
