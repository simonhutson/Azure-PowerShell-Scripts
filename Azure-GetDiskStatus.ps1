###############################################################################################################################
#
# Retrieve the status of all Azure Disks across all Subscriptions associated with a specific Azure AD Tenant
#
# NOTE: Make sure you have the correct versions of PowerShell installed, either 5.x (requires .NET )
#       All releases of PowerShell 6.x can be found at https://github.com/PowerShell/PowerShell/releases
#
#       >$PSVersionTable.PSVersion
#
# NOTE: Download latest Azure and AzureAD Powershell modules, using the following PowerShell commands with elevated privileges
#
#       >Install-Module -Name Az -AllowClobber -Force -Confirm
#       >Update-Module -Name Az
#       >Set-ExecutionPolicy RemoteSigned -Confirm -Force
#
###############################################################################################################################

#region Function Get-ChildObject

Function Get-ChildObject
{
    param(
        [System.Object]$Object,
        [string]$Path
    )
    process
    {
        $ReturnValue = ""
        if($Object -and $Path)
        {
            $EvaluationExpression = '$Object'

            foreach($Token in $Path.Split("."))
            {
                If($Token)
                {
                    $EvaluationExpression += '.' + $Token
                    if($null -ne (Invoke-Expression $EvaluationExpression))
                    {
                        $ReturnValue = Invoke-Expression $EvaluationExpression
                    }
                    else
                    {
                        $ReturnValue = ""
                    }
                }
            }
        }
        Write-Output -InputObject $ReturnValue
    }
}

#endregion

#region Check PowerShell Version

$PowerShellVersion = $PSVersionTable.PSVersion
if($PowerShellVersion.Major -lt 5)
{
    Write-Host -BackgroundColor Red -ForegroundColor White "PowerShell needs to be version 5 or above."
    Exit
}

#endregion

#region Set Globals

$ErrorActionPreference = 'Stop'
$DateTime = Get-Date -f 'yyyy-MM-dd HHmmss'

#endregion

#region Login

# Login to the user's default Azure AD Tenant
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Login to User's default Azure AD Tenant"
$Account = Connect-AzAccount
Write-Host

# Get the list of Azure AD Tenants this user has access to, and select the correct one
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Retrieving list of Azure AD Tenants for this User"
$Tenants = @(Get-AzTenant)
Write-Host

# Get the list of Azure AD Tenants this user has access to, and select the correct one
if($Tenants.Count -gt 1) # User has access to more than one Azure AD Tenant
{
    $Tenant = $Tenants |  Out-GridView -Title "Select the Azure AD Tenant you wish to use..." -OutputMode Single
}
elseif($Tenants.Count -eq 1) # User has access to only one Azure AD Tenant
{
    $Tenant = $Tenants.Item(0)
}
else # User has access to no Azure AD Tenant
{
    Return
}

# Check if the current Azure AD Tenant is the required Tenant
if($Account.Context.Tenant.Id -ne $Tenant.Id)
{
    # Login to the required Azure AD Tenant
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Login to correct Azure AD Tenant"
    $Account = Connect-AzAccount -Tenant $Tenant.Id
    Write-Host
}

# Get Authentication Access Token, for use with the Azure REST API
$TokenCache = (Get-AzContext).TokenCache
$Token = $TokenCache.ReadItems() | Where-Object { $_.TenantId -eq $Tenant.Id -and $_.DisplayableId -eq $Account.Context.Account.Id}
$AccessToken = "Bearer " + $Token.AccessToken

#endregion

#region Select subscription(s)

# Get list of Subscriptions associated with this Azure AD Tenant, for which this User has access
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Retrieving list of Azure Subscriptions for this Azure AD Tenant"
$AllSubscriptions = @(Get-AzSubscription -TenantId $Tenant.Id)
Write-Host

if($AllSubscriptions.Count -gt 1) # User has access to more than one Azure Subscription
{
    $SelectedSubscriptions = $AllSubscriptions |  Out-GridView -Title "Select the Azure Subscriptions you wish to use..." -OutputMode Multiple
}
elseif($AllSubscriptions.Count -eq 1) # User has access to only one Azure Subscription
{
    $SelectedSubscriptions = @($AllSubscriptions.Item(0))
}
else # User has access to no Azure Subscription
{
    Return
}

#endregion

#region Get ARM Disk Details

# Loop through each Subscription
foreach ($Subscription in $SelectedSubscriptions)
{

    # Set the current Azure context
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Setting context for Subscription: $($Subscription.Name)"
    $Context = Set-AzContext -SubscriptionId $Subscription -TenantId $Account.Context.Tenant.Id
    Write-Host

    # Get all the ARM VMs in the current Subscription
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Retrieving list of ARM VMs in Subscription: $($Subscription.Name)"
    $VMs = Get-AzResource -ResourceType Microsoft.Compute/virtualmachines -ExpandProperties
    Write-Host

    # Get all the ARM Disks in the current Subscription
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Retrieving list of ARM Disks in Subscription: $($Subscription.Name)"
    $Resources = Get-AzResource -ResourceType Microsoft.Compute/disks -ExpandProperties
    Write-Host

    # Create an empty Array to hold our custom Disk objects
    $Objects = [PSCustomObject]@()

    if($Resources)
    {
        Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Creating custom list of ARM Disks in Subscription: $($Subscription.Name)"
        foreach ($Resource in $Resources)
        {
            
            # Find the VM to which the Disk is attached
            $VM = $(if(Get-ChildObject -Object $Resource -Path Properties.diskState){$($VMs | Where-Object {$_.Properties.storageProfile.osDisk.name -eq $(Get-ChildObject -Object $Resource -Path Name) -or $_.Properties.storageProfile.dataDisks.name -eq $(Get-ChildObject -Object $Resource -Path Name)})})

            # Create a custom PowerShell object to hold the consolidated ARM Disk information
            $HashTable = [Ordered]@{
                "Created On" = $(if(Get-ChildObject -Object $Resource -Path Properties.timeCreated){[DateTime]::Parse($(Get-ChildObject -Object $Resource -Path Properties.timeCreated)).ToUniversalTime()})
                "Subscription" = $(Get-ChildObject -Object $Subscription -Path Name)
                "Resource Group" = $(Get-ChildObject -Object $Resource -Path ResourceGroupName)
                "Disk Name" = $(Get-ChildObject -Object $Resource -Path Name)
                "Disk Location" = $(Get-ChildObject -Object $Resource -Path Location)
                "Disk SKU Tier" = $(Get-ChildObject -Object $Resource -Path Sku.tier)
                "Disk SKU Name" = $(Get-ChildObject -Object $Resource -Path Sku.name)
                "Disk Size (GB)" = $([INT]$(Get-ChildObject -Object $Resource -Path Properties.diskSizeGB))
                "Disk IOPS" = $([INT]$(Get-ChildObject -Object $Resource -Path Properties.diskIOPSReadWrite))
                "Disk MBps" = $([INT]$(Get-ChildObject -Object $Resource -Path Properties.diskMBpsReadWrite))
                "Disk State" = $(Get-ChildObject -Object $Resource -Path Properties.diskState)
                "VM Name" = $(Get-ChildObject -Object $VM -Path Name)
                "VM Disk Type" = $(if($VM.Properties.storageProfile.osDisk.name -eq $(Get-ChildObject -Object $Resource -Path Name)){"OS Disk"}elseif($VM.Properties.storageProfile.dataDisks.name -eq $(Get-ChildObject -Object $Resource -Path Name)){"Data Disk"}else{""})
                "Provisioning State" = $(Get-ChildObject -Object $Resource -Path Properties.provisioningState)
                "Create Option" = $(Get-ChildObject -Object $Resource -Path Properties.creationData.createOption)
            }

            # Add the HashTable to the Custom Object Array
            $Objects += [PSCustomObject]$HashTable
            Write-Host -NoNewline "."
        }
        Write-Host
    }

    # Append to a CSV file on the user's Desktop
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Appending details of ARM Disks in Subscription: $($Subscription.Name) to file"
    $FilePath = "$env:HOMEDRIVE$env:HOMEPATH\Desktop\Azure Disk Status $($DateTime).csv"
    if($Objects){$Objects | Export-Csv -Path $FilePath -Append -NoTypeInformation}

    Write-Host

}

#endregion
