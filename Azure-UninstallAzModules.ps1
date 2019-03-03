###############################################################################################################################
#
# Uninstall all versions of the Az PowerShell Modules on the local machine
#
# NOTE: This requires local administrator priviliges and the latest PowerShellGet module
#
###############################################################################################################################


function Uninstall-AllModules {
    param(
      [Parameter(Mandatory=$true)]
      [string]$TargetModule,

      [Parameter(Mandatory=$true)]
      [string]$Version,

      [switch]$Force,

      [switch]$WhatIf,

      [switch]$Verbose
    )

    $AllModules = @()

    'Creating list of dependencies...'
    $target = Find-Module $TargetModule -RequiredVersion $version -Verbose:$Verbose
    $target.Dependencies | ForEach-Object {
      if ($_.requiredVersion) {
        $AllModules += New-Object -TypeName psobject -Property @{name=$_.name; version=$_.requiredVersion} -Verbose:$Verbose
      }
      else { # Assume minimum version
        # Minimum version actually reports the installed dependency
        # which is used, not the actual "minimum dependency." Check to
        # see if the requested version was installed as a dependency earlier.
        $candidate = Get-InstalledModule $_.name -RequiredVersion $version -Verbose:$Verbose
        if ($candidate) {
          $AllModules += New-Object -TypeName psobject -Property @{name=$_.name; version=$version}
        }
        else {
          Write-Warning ("Could not find uninstall candidate for {0}:{1} - module may require manual uninstall" -f $_.name,$version)
        }
      }
    }
    $AllModules += New-Object -TypeName psobject -Property @{name=$TargetModule; version=$Version}

    foreach ($module in $AllModules) {
      Write-Host ('Uninstalling {0} version {1}...' -f $module.name,$module.version)
      try {
        Uninstall-Module -Name $module.name -RequiredVersion $module.version -Force:$Force -ErrorAction Stop -WhatIf:$WhatIf -Verbose:$Verbose
      } catch {
        Write-Host ("`t" + $_.Exception.Message)
      }
    }
  }

if (!([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) { Start-Process powershell.exe "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" `"$args`"" -Verb RunAs; exit }

# Uninstall Az modules, all versions
# https://docs.microsoft.com/powershell/azure/uninstall-az-ps
$AzVersions = (Get-InstalledModule -Name "Az" -AllVersions -ErrorAction SilentlyContinue | Select-Object Version)
if ($AzVersions)
{
    $AzVersions[1..($AzVersions.Length)]  | ForEach-Object { Uninstall-AllModules -TargetModule "Az" -Version ($_.Version) -Force -Verbose }
}
