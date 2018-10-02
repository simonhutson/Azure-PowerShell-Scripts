###############################################################################################################################
#
# Retrieve the status of all Azure Storage Accounts across selected Subscriptions associated with a specific Azure AD Tenant
#
# Retrieve the status of all Azure Virtual Machines across all Subscriptions associated with a specific Azure AD Tenant
#
# NOTE: Download latest Azure and AzureAD Powershell modules, using the following PowerShell commands with elevated privileges
#
#       >Install-Module AzureRM -AllowClobber -Force -Confirm
#       >Install-Module AzureAD -AllowClobber -Force -Confirm
#       >Install-Module Az.ResourceGraph -AllowClobber -Force -Confirm
#       >Set-ExecutionPolicy RemoteSigned -Confirm -Force
#
# NOTE: Download latest version of Chocolatey package manager for Windows
#
#       >https://chocolatey.org/install
#
# NOTE: Download latest version of ArmClient
#
#       >https://chocolatey.org/packages/ARMClient
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
                    if((Invoke-Expression $EvaluationExpression) -ne $null)
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

$ErrorActionPreference = 'Stop'
$DateTime = Get-Date -f 'yyyy-MM-dd HHmmss'

#region Login

# Login to the user's default Azure AD Tenant
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Login to User's default Azure AD Tenant"
$Account = Add-AzureRmAccount
Write-Host

# Get the list of Azure AD Tenants this user has access to, and select the correct one
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Retrieving list of Azure AD Tenants for this User"
$Tenants = @(Get-AzureRmTenant)
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

# Get Authentication Token, just in case it is required in future
$TokenCache = (Get-AzureRmContext).TokenCache
$Token = $TokenCache.ReadItems() | Where-Object { $_.TenantId -eq $Tenant.Id }

# Check if the current Azure AD Tenant is the required Tenant
if($Account.Context.Tenant.Id -ne $Tenant.Id)
{
    # Login to the required Azure AD Tenant
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Login to correct Azure AD Tenant"
    $Account = Add-AzureRmAccount -TenantId $Tenant.Id
    Write-Host
}

#endregion

#region Select subscriptions

# Get list of Subscriptions associated with this Azure AD Tenant, for which this User has access
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Retrieving list of Azure Subscriptions for this Azure AD Tenant"
$AllSubscriptions = @(Get-AzureRmSubscription -TenantId $Tenant.Id)
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

#region ARM Storage Account details

# Loop through each Subscription
foreach ($Subscription in $SelectedSubscriptions)
{
    # Set the current Azure context
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Setting context for Subscription: $($Subscription.Name)"
    $Context = Set-AzureRmContext -SubscriptionId $Subscription -TenantId $Account.Context.Tenant.Id
    Write-Host

    # Get all the ARM Storage Accounts in the current Subscription
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Retrieving list of ARM Storage Accounts in Subscription: $($Subscription.Name)"
    $StorageAccounts = Get-AzureRmResource -ResourceType Microsoft.Storage/storageAccounts -ExpandProperties
    Write-Host

    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Creating custom list of ARM Storage Accounts in Subscription: $($Subscription.Name)"              

    # Create an empty Array to hold our custom VM objects
    $StorageAccountObjects = [PSCustomObject]@()

    if($StorageAccounts)
    {
        foreach ($StorageAccount in $StorageAccounts)
        {
            $StorageAccountHashTable = [Ordered]@{
                "Created On" = $(if(Get-ChildObject -Object $StorageAccount -Path Properties.creationTime){[DateTime]::Parse($(Get-ChildObject -Object $StorageAccount -Path Properties.creationTime)).ToUniversalTime()})
                "Subscription" = $($Subscription.Name)
                "Resource Group" = $(Get-ChildObject -Object $StorageAccount -Path ResourceGroupName)
                "Storage Account" = $(Get-ChildObject -Object $StorageAccount -Path ResourceName)
                "Location" = $(Get-ChildObject -Object $StorageAccount -Path Location)
                "Kind" = $(Get-ChildObject -Object $StorageAccount -Path Kind)
                "Sku Name" = $(Get-ChildObject -Object $StorageAccount -Path Sku.Name)
                "Sku Tier" = $(Get-ChildObject -Object $StorageAccount -Path Sku.Tier)
                "CustomDomain" = $(Get-ChildObject -Object $StorageAccount -Path Properties.customDomain.name)
                "AccessTier" = $(Get-ChildObject -Object $StorageAccount -Path Properties.accesTier)
                "HTTPS Only" = $(Get-ChildObject -Object $StorageAccount -Path Properties.supportsHttpsTrafficOnly)
                "Primary Location" = $(Get-ChildObject -Object $StorageAccount -Path Properties.primaryLocation)
                "Status of Primary" = $(Get-ChildObject -Object $StorageAccount -Path Properties.statusOfPrimary)
                "Secondary Location" = $(Get-ChildObject -Object $StorageAccount -Path Properties.secondaryLocation)
                "Status of Secondary" = $(Get-ChildObject -Object $StorageAccount -Path Properties.statusOfSecondary)
                "Encryption Key Source" = $(Get-ChildObject -Object $StorageAccount -Path Properties.encryption.keysource)
            }

            # Add the VM HashTable to the Custom Object Array
            $StorageAccountObjects += [PSCustomObject]$StorageAccountHashTable
            Write-Host -NoNewline "."
        }
    }
    # Output to a CSV file on the user's Desktop
    $FilePath = "$env:HOMEDRIVE$env:HOMEPATH\Desktop\Azure Storage Account Status $($DateTime) (ARM).csv"
    if($StorageAccountObjects){$StorageAccountObjects | Export-Csv -Path $FilePath -Append -NoTypeInformation}
    Write-Host
}

#endregion

#region Classic Storage Account Details

# Loop through each Subscription
foreach ($Subscription in $SelectedSubscriptions)
{
    # Set the current Azure context
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Setting context for Subscription: $($Subscription.Name)"
    $Context = Set-AzureRmContext -SubscriptionId $Subscription.Id -TenantId $Account.Context.Tenant.Id
    Write-Host

    # Get all the Classic Storage Accounts in the current Subscription
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Retrieving list of Classic Storage Accounts in Subscription: $($Subscription.Name)"
    $StorageAccounts = Get-AzureRmResource -ResourceType Microsoft.ClassicStorage/storageAccounts -ExpandProperties
    Write-Host

    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Creating custom list of Classic Storage Accounts in Subscription: $($Subscription.Name)"              

    # Create an empty Array to hold our custom VM objects
    $StorageAccountObjects = [PSCustomObject]@()

    if($StorageAccounts)
    {
        foreach ($StorageAccount in $StorageAccounts)
        {
           $StorageAccountHashTable = [Ordered]@{
                "Created On" = $(if(Get-ChildObject -Object $StorageAccount -Path Properties.creationTime){[DateTime]::Parse($(Get-ChildObject -Object $StorageAccount -Path Properties.creationTime)).ToUniversalTime()})
                "Subscription" = $($Subscription.Name)
                "Resource Group" = $(Get-ChildObject -Object $StorageAccount -Path ResourceGroupName)
                "Storage Account" = $(Get-ChildObject -Object $StorageAccount -Path ResourceName)
                "Location" = $(Get-ChildObject -Object $StorageAccount -Path Location)
                "Kind" = $(Get-ChildObject -Object $StorageAccount -Path Kind)
                "Account Type" = $(Get-ChildObject -Object $StorageAccount -Path Properties.accountType)
                "Primary Location" = $(Get-ChildObject -Object $StorageAccount -Path Properties.geoPrimaryRegion)
                "Status of Primary" = $(Get-ChildObject -Object $StorageAccount -Path Properties.statusOfPrimaryRegion)
                "Secondary Location" = $(Get-ChildObject -Object $StorageAccount -Path Properties.geoSecondaryRegion)
                "Status of Secondary" = $(Get-ChildObject -Object $StorageAccount -Path Properties.statusOfSecondaryRegion)
            }

            # Add the VM HashTable to the Custom Object Array
            $StorageAccountObjects += [PSCustomObject]$StorageAccountHashTable
            Write-Host -NoNewline "."
        }
    }
    # Output to a CSV file on the user's Desktop
    $FilePath = "$env:HOMEDRIVE$env:HOMEPATH\Desktop\Azure Storage Account Status $($DateTime) (Classic).csv"
    if($StorageAccountObjects){$StorageAccountObjects | Export-Csv -Path $FilePath -Append -NoTypeInformation}
    Write-Host
}

#endregion
