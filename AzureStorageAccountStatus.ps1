###############################################################################################################################
#
# Retrieve the status of all Azure Storage Accounts across selected Subscriptions associated with a specific Azure AD Tenant
#
# NOTE: Download latest Azure and AzureRM Powershell modules, using the following PowerShell commands with elevated privileges
#
#       >Install-Module AzureRM -AllowClobber -Force -Confirm
#       >Install-Module Azure -AllowClobber -Force -Confirm
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
$Account = Connect-AzureRmAccount
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
$Subscriptions = @(Get-AzureRmSubscription -TenantId $Tenant.Id)
Write-Host

if($Subscriptions.Count -gt 1) # User has access to more than one Azure Subscription
{
    $Subscriptions = $Subscriptions |  Out-GridView -Title "Select the Azure Subscriptions you wish to use..." -OutputMode Multiple
}
elseif($Subscriptions.Count -eq 1) # User has access to only one Azure Subscription
{
    $Subscriptions = @($Subscriptions.Item(0))
}
else # User has access to no Azure Subscription
{
    Return
}

#endregion

#region ARM Storage Account details

# Loop through each Subscription
foreach ($Subscription in $Subscriptions)
{

    $StorageAccountObjects = @()

    # Set the current Azure context
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Setting context for Subscription: $($Subscription.Name)"
    $Context = Set-AzureRmContext -SubscriptionId $Subscription.Id -TenantId $Account.Context.Tenant.Id
    #$Context = Set-AzureRmContext -SubscriptionId a8d854f2-407b-4bbe-9575-11cc184a7aa3 -TenantId $Account.Context.Tenant.Id
    Write-Host

    # Get all the ARM Storage Accounts in the current Subscription
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Retrieving list of ARM Storage Accounts in Subscription: $($Subscription.Name)"
    $StorageAccounts = Get-AzureRmResource -ResourceType Microsoft.Storage/storageAccounts -ExpandProperties
    #$StorageAccounts = Get-AzureRmStorageAccount

    Write-Host

    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Creating custom list of Storage Accounts in Subscription: $($Subscription.Name)"              

    if($StorageAccounts)
    {
        foreach ($StorageAccount in $StorageAccounts)
        {
            # Create a custom PowerShell object to hold the consolidated ARM VM information
            $StorageAccountObject = New-Object PSObject
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Subscription" -Value $($Subscription.Name)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Resource Group" -Value $(Get-ChildObject -Object $StorageAccount -Path ResourceGroupName)
            #$StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Storage Account" -Value $(Get-ChildObject -Object $StorageAccount -Path StorageAccountName)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Storage Account" -Value $(Get-ChildObject -Object $StorageAccount -Path ResourceName)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Location" -Value $(Get-ChildObject -Object $StorageAccount -Path Location)
            #$StorageAccountObject | Add-Member -MemberType NoteProperty -Name "CreationTime" -Value $(Get-ChildObject -Object $StorageAccount -Path CreationTime.DateTime)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "CreationTime" -Value $(Get-ChildObject -Object $StorageAccount -Path Properties.creationTime)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Kind" -Value $(Get-ChildObject -Object $StorageAccount -Path Kind)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Sku Name" -Value $(Get-ChildObject -Object $StorageAccount -Path Sku.Name)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Sku Tier" -Value $(Get-ChildObject -Object $StorageAccount -Path Sku.Tier)
            #$StorageAccountObject | Add-Member -MemberType NoteProperty -Name "CustomDomain" -Value $(Get-ChildObject -Object $StorageAccount -Path CustomDomain)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "CustomDomain" -Value $(Get-ChildObject -Object $StorageAccount -Path Properties.customDomain.name)
            #$StorageAccountObject | Add-Member -MemberType NoteProperty -Name "AccessTier" -Value $(Get-ChildObject -Object $StorageAccount -Path AccesTier)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "AccessTier" -Value $(Get-ChildObject -Object $StorageAccount -Path Properties.accesTier)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Identity PrincipalId" -Value $(Get-ChildObject -Object $StorageAccount -Path Identity.PrincipalId)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Identity TenantId" -Value $(Get-ChildObject -Object $StorageAccount -Path Identity.TenantId)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Identity Type" -Value $(Get-ChildObject -Object $StorageAccount -Path Identity.Type)
            #$StorageAccountObject | Add-Member -MemberType NoteProperty -Name "HTTPS Only" -Value $(Get-ChildObject -Object $StorageAccount -Path EnableHttpsTrafficOnly)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "HTTPS Only" -Value $(Get-ChildObject -Object $StorageAccount -Path Properties.supportsHttpsTrafficOnly)
            #$StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Primary Location" -Value $(Get-ChildObject -Object $StorageAccount -Path PrimaryLocation)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Primary Location" -Value $(Get-ChildObject -Object $StorageAccount -Path Properties.primaryLocation)
            #$StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Status of Primary" -Value $(Get-ChildObject -Object $StorageAccount -Path StatusOfPrimary)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Status of Primary" -Value $(Get-ChildObject -Object $StorageAccount -Path Properties.statusOfPrimary)
            #$StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Encryption Key Source" -Value $(Get-ChildObject -Object $StorageAccount -Path Encryption.Keysource)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Encryption Key Source" -Value $(Get-ChildObject -Object $StorageAccount -Path Properties.encryption.keysource)
            #$StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Blob Encryption" -Value $(Get-ChildObject -Object $StorageAccount -Path Encryption.Services.Blob.Enabled)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Blob Encryption" -Value $(Get-ChildObject -Object $StorageAccount -Path Properties.encryption.services.blob.enabled)
            #$StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Blob Encryption LastEnabledTime" -Value $(Get-ChildObject -Object $StorageAccount -Path Encryption.Services.Blob.LastEnabledTime.DateTime)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Blob Encryption LastEnabledTime" -Value $(Get-ChildObject -Object $StorageAccount -Path Properties.encryption.services.blob.lastEnabledTime)
            #$StorageAccountObject | Add-Member -MemberType NoteProperty -Name "File Encryption" -Value $(Get-ChildObject -Object $StorageAccount -Path Encryption.Services.File.Enabled)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "File Encryption" -Value $(Get-ChildObject -Object $StorageAccount -Path Properties.encryption.services.file.enabled)
            #$StorageAccountObject | Add-Member -MemberType NoteProperty -Name "File Encryption LastEnabledTime" -Value $(Get-ChildObject -Object $StorageAccount -Path Encryption.Services.File.LastEnabledTime.DateTime)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "File Encryption LastEnabledTime" -Value $(Get-ChildObject -Object $StorageAccount -Path Properties.encryption.services.file.lastEnabledTime)

            # Add the custom Storage Account object to the Array
            $StorageAccountObjects += $StorageAccountObject
            Write-Host -NoNewline "."
        }
    }
    Write-Host

    # Output to a CSV file on the user's Desktop
    $FilePath = "$env:HOMEDRIVE$env:HOMEPATH\Desktop\Azure Storage Account Status $($DateTime) (ARM).csv"
    if($StorageAccountObjects){$StorageAccountObjects | Export-Csv -Path $FilePath -Append -NoTypeInformation}
    Write-Host

}

#endregion

#region Classic Storage Account Details

# Loop through each Subscription
foreach ($Subscription in $Subscriptions)
{

    $StorageAccountObjects = @()

    # Set the current Azure context
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Setting context for Subscription: $($Subscription.Name)"
    $Context = Set-AzureRmContext -SubscriptionId $Subscription.Id -TenantId $Account.Context.Tenant.Id
    Write-Host

    # Get all the Classic Storage Accounts in the current Subscription
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Retrieving list of Classic Storage Accounts in Subscription: $($Subscription.Name)"
    #$StorageAccounts = Get-AzureStorageAccount
    $StorageAccounts = Get-AzureRmResource -ResourceType Microsoft.ClassicStorage/storageAccounts -ExpandProperties
    Write-Host

    if($StorageAccounts)
    {
        foreach ($StorageAccount in $StorageAccounts)
        {
            # Create a custom PowerShell object to hold the consolidated ARM VM information
            $StorageAccountObject = New-Object PSObject
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Subscription" -Value $($Subscription.Name)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Resource Group" -Value $(Get-ChildObject -Object $StorageAccount -Path ResourceGroupName)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Storage Account" -Value $(Get-ChildObject -Object $StorageAccount -Path ResourceName)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Location" -Value $(Get-ChildObject -Object $StorageAccount -Path Location)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "CreationTime" -Value $(Get-ChildObject -Object $StorageAccount -Path Properties.creationTime)
            $StorageAccountObject | Add-Member -MemberType NoteProperty -Name "Account Type" -Value $(Get-ChildObject -Object $StorageAccount -Path Properties.accountType)

            # Add the custom Storage Account object to the Array
            $StorageAccountObjects += $StorageAccountObject
            Write-Host -NoNewline "."

        }
        Write-Host
    }

    # Output to a CSV file on the user's Desktop
    $FilePath = "$env:HOMEDRIVE$env:HOMEPATH\Desktop\Azure Storage Account Status $($DateTime) (Classic).csv"
    if($StorageAccountObjects){$StorageAccountObjects | Export-Csv -Path $FilePath -Append -NoTypeInformation}
}

#endregion
