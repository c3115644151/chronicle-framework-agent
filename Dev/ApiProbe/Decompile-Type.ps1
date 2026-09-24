[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Assembly,
    [Parameter(Mandatory)]
    [string]$Type
)

$ErrorActionPreference = 'Stop'
$ilspy = Get-Command ilspycmd -ErrorAction Stop
$assemblyPath = Resolve-Path $Assembly
& $ilspy.Source -t $Type $assemblyPath.Path
if ($LASTEXITCODE -ne 0) {
    throw "ILSpy failed for type '$Type'."
}
