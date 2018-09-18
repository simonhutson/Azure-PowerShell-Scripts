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

$ErrorActionPreference = 'Continue'

$DateTime = Get-Date -f 'yyyy-MM-dd HHmmss'

#region Login

# Login to the user's default Azure AD Tenant
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Login to User's default Azure AD Tenant"
$Account = Add-AzureRmAccount
Write-Host

# Get the list of Azure AD Tenants this user has access to, and select the correct one
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Retrieving list of Azure AD Tenants for this User"
$Tenants = Get-AzureRmTenant
if($Tenants.Count -gt 1) # User has access to more than one Azure AD Tenant
{
    $Tenant = $Tenants | select-object -property Id | Out-GridView -Title "Select the Azure AD Tenant you wish to use..." -PassThru
}
else # User has access to only one Azure AD Tenant
{
    $Tenant = $Tenants.Item(0)
}
Write-Host


if($Account.Context.Tenant.Id -ne $Tenant.Id)
{
    # Login to the correct Azure AD Tenant
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Login to correct Azure AD Tenant"
    $Account = Add-AzureRmAccount -TenantId $Tenant.Id
    Write-Host
}

#endregion

#region ARM Backup Item Details

# Create empty Arrays to hold our custom Backup Item objects
$BackupItemObjects = @()
$EmptyBackupVaultObjects = @()

# Get list of Subscriptions associated with this Azure AD Tenant, for which this User has access
Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Retrieving list of Azure Subscriptions for this Azure AD Tenant"
$Subscriptions = Get-AzureRmSubscription -TenantId $Tenant.Id
Write-Host

foreach ($Subscription in $Subscriptions)
{
    # Set the current Azure context
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Setting context for Subscription: $($Subscription.Name)"
    $Context = Set-AzureRmContext -SubscriptionId $Subscription -TenantId $Account.Context.Tenant.Id
    Write-Host

    # Get the Azure authentication Token
    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Getting the current user Authentication Token"
    $TokenCache = (Get-AzureRmContext).TokenCache
    $Token = $TokenCache.ReadItems() | Where-Object { $_.TenantId -eq $Tenant.Id }
    Write-Host

    Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Getting the Recovery Services Vaults in Subscription: $($Subscription.Name)"
    $BackupVaults = Get-AzureRmRecoveryServicesVault
    Write-Host

    #loop through each backup vault
    foreach ($BackupVault in $BackupVaults)
    {
        #Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Setting the context to Recovery Service Vault: $($BackupVault.Name)"
        Set-AzureRmRecoveryServicesVaultContext -Vault $BackupVault
        #Write-Host

        #Write-Host -BackgroundColor Yellow -ForegroundColor DarkBlue "Getting the Containers in Recovery Service Vault: $($BackupVault.Name)"
        $BackupContainers = Get-AzureRmRecoveryServicesBackupContainer -ContainerType AzureVM -BackupManagementType AzureVM
        #Write-Host

        if($BackupContainers)
        {
            foreach ($BackupContainer in $BackupContainers)
            {
                # Get the Backup Item for the current Backup container
                $BackupItem = Get-AzureRmRecoveryServicesBackupItem -Container $BackupContainer -WorkloadType AzureVM

                # Check see if the Virtual Machine associated with the Backup Item still exists
                try
                {
                    $Resource = Get-AzureRmResource -ResourceId $BackupItem.VirtualMachineId -ErrorAction SilentlyContinue
                }
                catch
                {
                    $Resource = $null
                }

                # Create a custom PowerShell object to hold the consolidated Backup Item information
                $BackupItemObject = New-Object PSObject
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "Vault Subscription" -Value $(Get-ChildObject -Object $Subscription -Path Name)
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "Vault Resource Group" -Value $(Get-ChildObject -Object $BackupVault -Path ResourceGroupName)
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "Vault Name" -Value $(Get-ChildObject -Object $BackupVault -Path Name)
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "Vault Location" -Value $(Get-ChildObject -Object $BackupVault -Path Location)
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "Vault Provisioning State" -Value $(Get-ChildObject -Object $BackupVault -Path Properties.ProvisioningState)
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "Container Name" -Value $(Get-ChildObject -Object $BackupContainer -Path FriendlyName)
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "Container Type" -Value $(Get-ChildObject -Object $BackupContainer -Path ContainerType)
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "Container Status" -Value $(Get-ChildObject -Object $BackupContainer -Path Status)
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "Protection Policy Name" -Value $(Get-ChildObject -Object $BackupItem -Path ProtectionPolicyName)
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "VM Name" -Value $((Get-ChildObject -Object $BackupItem -Path VirtualMachineId).Split("/")[8])
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "VM Resource Group" -Value $((Get-ChildObject -Object $BackupItem -Path VirtualMachineId).Split("/")[4])
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "VM Exists" -Value $(if($Resource){"Exists"}else{"Does Not Exist"})
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "VM Type" -Value $(if((Get-ChildObject -Object $Resource -Path ResourceType) -eq "Microsoft.Compute/virtualMachines"){"ARM"}else{"Classic"})
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "VM Protection Status" -Value $(Get-ChildObject -Object $BackupItem -Path ProtectionStatus)
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "VM Protection State" -Value $(Get-ChildObject -Object $BackupItem -Path ProtectionState)
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "VM Last Backup Status" -Value $(Get-ChildObject -Object $BackupItem -Path LastBackupStatus)
                $BackupItemObject | Add-Member -MemberType NoteProperty -Name "VM Last Backup Time" -Value $([System.DateTime](Get-ChildObject -Object $BackupItem -Path LastBackupTime))

                # Add the custom Backup Item objects to the Array
                $BackupItemObjects += $BackupItemObject
                Write-Host -NoNewline "."
            }
        }
        else
        {
            # Create a custom PowerShell object to hold the empty Backup Vault information
            $EmptyBackupVaultObject = New-Object PSObject
            $EmptyBackupVaultObject | Add-Member -MemberType NoteProperty -Name "Vault Subscription" -Value $(Get-ChildObject -Object $Subscription -Path Name)
            $EmptyBackupVaultObject | Add-Member -MemberType NoteProperty -Name "Vault Resource Group" -Value $(Get-ChildObject -Object $BackupVault -Path ResourceGroupName)
            $EmptyBackupVaultObject | Add-Member -MemberType NoteProperty -Name "Vault Name" -Value $(Get-ChildObject -Object $BackupVault -Path Name)
            $EmptyBackupVaultObject | Add-Member -MemberType NoteProperty -Name "Vault Location" -Value $(Get-ChildObject -Object $BackupVault -Path Location)
            $EmptyBackupVaultObject | Add-Member -MemberType NoteProperty -Name "Vault Provisioning State" -Value $(Get-ChildObject -Object $BackupVault -Path Properties.ProvisioningState)


            # Add the custom Backup Item objects to the Array
            $EmptyBackupVaultObjects += $EmptyBackupVaultObject
            Write-Host -NoNewline "."

        }
    }
    Write-Host
}

# Output to CSV files on the user's Desktop
$BackupItemFilePath = "$env:HOMEDRIVE$env:HOMEPATH\Desktop\Azure Backup Item Status $($DateTime).csv"
if($BackupItemObjects){$BackupItemObjects | Export-Csv -Path $BackupItemFilePath -NoTypeInformation}

$EmptyBackupVaultFilePath = "$env:HOMEDRIVE$env:HOMEPATH\Desktop\Azure Empty Backup Vaults $($DateTime).csv"
if($EmptyBackupVaultObjects){$EmptyBackupVaultObjects | Export-Csv -Path $EmptyBackupVaultFilePath -NoTypeInformation}

#endregion
