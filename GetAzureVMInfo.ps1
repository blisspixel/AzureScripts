<#
.SYNOPSIS
    Azure VM Details Exporter

.DESCRIPTION
    This PowerShell script systematically gathers and exports a detailed inventory of Azure Virtual Machines (VMs) within a specified subscription. It captures essential information such as VM name, size (VM type), number of CPUs, amount of RAM, total disk size, as well as the associated region and resource group. This data is then neatly exported to a CSV file for documentation, analysis, or auditing purposes.

.NOTES
    File Name      : GetAzureVMInfo.ps1
    Version        : 1.0
    Prerequisite   : Install Azure PowerShell module (Install-Module -Name Az)
    Azure Permissions Required: Reader role or higher on the subscription.
    Usage          : Follow the on-screen prompts to specify the CSV file path and Azure Subscription IDs.
    Legal Disclaimer:
        This script is provided "as is" with no warranties, and confers no rights. Use of the script is at your own risk. The author or the entity represented by the author will not be liable for any damages incurred due to the use of the script.

.EXAMPLE
    PS> .\GetAzureVMInfo.ps1
    This example runs the script, which will prompt for the local CSV file path to export the details and the Azure Subscription IDs to query for VM information.

#>

# Function to retrieve VM details for a single subscription
function Get-VMDetails {
    param (
        [string]$subscriptionId,
        [string]$outputCsv
    )

    try {
        Write-Host "Attempting to connect to Azure account..."
        $null = Connect-AzAccount -Subscription $subscriptionId -ErrorAction Stop
        Write-Host "Successfully connected to Azure."

        $vmDetails = @()
        $resourceGroups = Get-AzResourceGroup
        Write-Host "Fetched resource groups from Azure."

        foreach ($resourceGroup in $resourceGroups) {
            Write-Host "Processing Resource Group: $($resourceGroup.ResourceGroupName)"
            $vms = Get-AzVM -ResourceGroupName $resourceGroup.ResourceGroupName

            if ($vms.Count -eq 0) {
                Write-Host "No VMs found in Resource Group: $($resourceGroup.ResourceGroupName)"
                continue
            }

            foreach ($vm in $vms) {
                Write-Host "Processing VM: $($vm.Name)"
                try {
                    $vmSizeDetails = Get-AzVMSize -Location $vm.Location | Where-Object { $_.Name -eq $vm.HardwareProfile.VmSize }
                    $vmInstanceView = Get-AzVM -ResourceGroupName $resourceGroup.ResourceGroupName -Name $vm.Name -Status
                    $networkInterfaces = Get-AzNetworkInterface -ResourceGroupName $resourceGroup.ResourceGroupName | Where-Object { $_.VirtualMachine.Id -eq $vm.Id }

                    # Initialize IP address strings
                    $privateIPsString = ''
                    $publicIPsString = ''

                    foreach ($nic in $networkInterfaces) {
                        foreach ($ipConfig in $nic.IpConfigurations) {
                            if ($ipConfig.PrivateIpAddress) {
                                $privateIPsString += $ipConfig.PrivateIpAddress + ', '
                            }
                            if ($ipConfig.PublicIpAddress) {
                                $publicIp = Get-AzPublicIpAddress -Name $ipConfig.PublicIpAddress.Id.Split('/')[-1] -ResourceGroupName $resourceGroup.ResourceGroupName
                                $publicIPsString += $publicIp.IpAddress + ', '
                            }
                        }
                    }

                    # Trim trailing commas
                    $privateIPsString = $privateIPsString.TrimEnd(', ')
                    $publicIPsString = $publicIPsString.TrimEnd(', ')

                    # Processing Disk Details
                    $osDiskSize = $vm.StorageProfile.OsDisk.DiskSizeGB
                    $dataDiskSizes = $vm.StorageProfile.DataDisks | ForEach-Object { $_.DiskSizeGB } | Measure-Object -Sum
                    $totalDiskSize = $osDiskSize + $dataDiskSizes.Sum

                    # Construct VM detail object
                    $vmDetail = @{
                        VMName              = $vm.Name
                        VMType              = $vm.HardwareProfile.VmSize
                        CPU                 = $vmSizeDetails.NumberOfCores
                        RAM                 = $vmSizeDetails.MemoryInMB
                        DiskSizeGB          = $totalDiskSize
                        Region              = $vm.Location
                        ResourceGroupName   = $resourceGroup.ResourceGroupName
                        PrivateIPs          = $privateIPsString
                        PublicIPs           = $publicIPsString
                    }

                    $vmDetails += New-Object PSObject -Property $vmDetail
                }
                catch {
                    Write-Host "Error fetching details for VM: $($vm.Name). Error: $_" -ForegroundColor Red
                }
            }
        }

        # Export the details to CSV, ensuring the order of columns
        $vmDetails | Select-Object VMName, VMType, CPU, RAM, DiskSizeGB, Region, ResourceGroupName, PrivateIPs, PublicIPs | Export-Csv -Path $outputCsv -NoTypeInformation
        Write-Host "VM details exported to $outputCsv for Subscription: $subscriptionId"
    }
    catch {
        Write-Host "Error while processing: $_" -ForegroundColor Red
    }
    finally {
        Disconnect-AzAccount
        Write-Host "Disconnected from Azure account."
    }
}

# Main script execution
Clear-Host
Write-Host "Azure VM Details Exporter"

$outputCsv = Read-Host "Enter CSV File Path (e.g., C:\AzureVMDetails.csv)"
$subscriptionIds = (Read-Host "Enter Azure Subscription IDs (comma-separated)").Split(',')

foreach ($subscriptionId in $subscriptionIds) {
    Write-Host "Processing Subscription ID: $subscriptionId"
    Get-VMDetails -subscriptionId $subscriptionId.Trim() -outputCsv $outputCsv
}

Write-Host "Azure VM details export process completed."
