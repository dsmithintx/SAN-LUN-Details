#
<#
ESXi Host ScsiLun, Paths, SanID, Vendor, Model, CanonicalName,LunID, Count, PathState, Policy Summary
Created May 2015
Author: Don Smith

Summary:
	Reports per ESXi host, per LUN: Hostname, ClusterName, Number of paths per LUN, SanID, Vendor, Model, CanonicalName, ArraySerial(EMC),LunHexID(EMC),LunSize, DatastoreName, LunID, DatastoreCapacity,
	PathState, PathPolicy, RR IOps, PathOperationalState, QueuDepth and Uuid

Requirements:
	VMware vSphere PowerCLI 5.x - https://www.vmware.com/


Script Updates Needed:
	Use regex instead of the Powershell 'split' method for line 153
	Add NFS mount information, i.e. Name					RemoteHost	RemotePath
									Mount_Name          	NAS_Host	/vol/nfs/share

Change Log:
	05/04/2015 - Initial creation
	05/07/2015 - Added datastore hash table to cross reference datastore names to naa ID's
	05/11/2015 - Added Queue Depth and Uuid
	05/12/2015 - Added LUN size
	05/14/2015 - Added Write-Progress
	05/19/2015 - Added Try/Catch check for PowerCLI installed
	05/28/2015 - Added NFS info
	06/05/2015 - Added EMC Array Serial number and Lun ID (in hex)
	06/10/2015 - Added Multi vCenters
	09/24/2015 - Added Esxcli/RR IOps info
	10/09/2015 - Added Lun Path SATP info
	10/29/2015 - Added LUN Target Port
	11/11/2015 - Added Device Operational State 'Detached' details
	12/02/2016 - Added ATS for VMFS HeartBeat info
	11/30/2017 - Added encrypted password

#>
#
$Filename = "C:\Temp2\ESXiHost_ScsiLun_Paths_SanID_Vendor_Model_CanonicalName_LunID_Count_PathState_Policy_Report-v10-{0:yyyy_MM_dd hh}.csv" -f (Get-Date)
#
$Report = @()
#
#$vCenters = "vCenter_name"

Foreach($vCenter in $vCenters){

	try {
        Connect-VIServer $vCenter -User vc_user -Password vc_pass -ErrorAction Stop
    }
    catch {
        Write-Host -f Yellow $_.Exception.Message
        CONTINUE
    }
# Collect Datastore Info and convert to hash table
	Write-Host -Object ('{0:yyyy-MM-dd HH:mm:ss } - Collecting Datastore Data...' -f (Get-Date))
	$DSHashTable = Get-View -ViewType Datastore -Property Info,Summary.Accessible,Summary.Type -Filter @{"Summary.Type"="VMFS"} | Select-Object `
		@{N="DSName";E={$_.Info.Vmfs.Name}},
		@{N="Mounted";E={$_.Summary.Accessible}},
		@{N="Capacity";E={"{0:N}" -f (($_.Info.Vmfs.Capacity/1GB),0)}},
		@{N="NaaId";E={$_.Info.Vmfs.Extent[0].DiskName}},
		@{N="Uuid";E={$_.Info.Vmfs.Uuid}}	| Group-Object "NaaId" -AsHashTable -AsString
	Write-Host -Object ('{0:yyyy-MM-dd HH:mm:ss } - Datastore Data Collection Completed...' -f (Get-Date))
#
	Write-Host -Object ('{0:yyyy-MM-dd HH:mm:ss } - Collecting Host Data...' -f (Get-Date))
# Uncomment ONLY a single line below
	$VMHosts = Get-View -ViewType HostSystem -Property Name,Config.StorageDevice,Parent,ConfigManager													# ALL hosts in a vCenter
#	$VMHosts = Get-View -ViewType HostSystem -Property Name,Config.StorageDevice,Parent,ConfigManager -SearchRoot (Get-Cluster "cluster_name").id	    # ALL hosts in a cluster
#	$VMHosts = Get-View -ViewType HostSystem -Property Name,Config.StorageDevice,Parent,ConfigManager -Filter @{"Name"="esxi_host.domain.com"}	        # SINGLE host in a vCenter
	Write-Host -Object ('{0:yyyy-MM-dd HH:mm:ss } - Host Data Collection Completed...' -f (Get-Date))
	$i = 0
#
	Foreach ($VMHost in $VMHosts){
		$i++
		Write-Progress -Activity "Scanning hosts" -Status ("Host: {0}" -f $VMHost.Name) -PercentComplete ($i/$VMHosts.count*100) -Id 0
		$HSS = Get-View $VMHost.ConfigManager.StorageSystem -Property StorageDeviceInfo,FileSystemVolumeInfo
#		$HBAs = $HSS.StorageDeviceInfo.HostBusAdapter | ?{$_.GetType().Name -eq "HostFibreChannelHba"}
		$ScsiLuns = $HSS | %{$_.StorageDeviceInfo.ScsiLun} | Select-Object -unique *
#		$UUIDs = $ScsiLuns | Select -unique UUID
#		$DatastoreInfo = $HSS | %{$_.FileSystemVolumeInfo.MountInfo} | %{$_.Volume} | Select -Unique *
#		$NFSInfo = $HSS | %{$_.FileSystemVolumeInfo.MountInfo} | ?{$_.Volume -is [VMware.Vim.HostNasVolume]}
		$HostLuns = $HSS | %{$_.StorageDeviceInfo.ScsiTopology.Adapter} | %{$_.Target | %{$_.LUN}} | Select-Object -unique *
		$PathInfo = $HSS.StorageDeviceInfo.MultipathInfo.Lun
		$esxcli = Get-EsxCli -VMHost $VMHost.Name
		$RRDevs = $esxcli.storage.nmp.device.list() | ?{$_.PathSelectionPolicy -eq "VMW_PSP_RR"}
#
		$ATSVMFSHeartBeat = Get-AdvancedSetting -Entity $VMHost.Name -Name VMFS3.UseATSForHBOnVMFS5
#
		$j=0
		Foreach($Lun in $ScsiLuns){
			$j++
			Write-Progress -Activity "Scanning LUNs" -Status ("LUN: {0}" -f $Lun.DisplayName) -PercentComplete ($j/$ScsiLuns.count*100) -Id 1
			$HostScsiLun = $HSS.StorageDeviceInfo.ScsiLun | ?{$_.Key -eq $Lun.Key}
			$LunSize = $HostScsiLun.Capacity.Block * $HostScsiLun.Capacity.BlockSize
			$ScsiLunID = $HSS.StorageDeviceInfo.ScsiTopology | %{$_.Adapter} | %{$_.Target} | %{$_.Lun}
			$LunID = ($HostLuns | ?{ $_.ScsiLun -eq $HostScsiLun.Key } | Select-Object -unique LUN).LUN
			$LunPaths = $PathInfo | ?{$_.Lun -eq $Lun.Key} #| %{$_.Path}
			$LunPathSATP = $LunPaths.StorageArrayTypePolicy.Policy
##			$PathNames = ($LunPaths | %{$_.Path} | Select -Unique Name).Name
			$HostLun = $ScsiLuns | ?{$_.Uuid -eq $Lun.Uuid} | Select-Object -First 1
			$NaaId = $HostScsiLun.CanonicalName
			$RRIOps = $RRDevs | ?{$_.Device -eq $NaaId}
#
			$row = "" | Select-Object vCenter,HostName,Cluster,NumPaths,Target,Vendor,Model,CanonicalName,ArraySerial,LunHexID,LunSize,DSName,LunID,DSCapacityGB,State,LunPathSATP,Policy,RRIOpsSetting,DeviceOpState,QueueDepth,Uuid,ATSVMFSHB
			$row.vCenter = $vCenter
			$row.Hostname = $VMHost.Name
			$row.Cluster = (Get-VIObjectByVIView $VMHost.Parent).Name
			$row.NumPaths = ($LunPaths | %{$_.Path}).Count
			$TargetNode = ("{0:x}" -f $LunPaths.Path[0].Transport.NodeWorldWideName) -replace '(..(?!$))','$1:'
#			$TargetPort = ("{0:x}" -f $LunPaths.Path[0].Transport.PortWorldWideName) -replace '(..(?!$))','$1:'
			$row.Target = $TargetNode #+ " " + $TargetPort
			$row.Vendor = $HostScsiLun.Vendor
			$row.Model = $HostScsiLun.Model
			$row.CanonicalName = $HostScsiLun.CanonicalName
			$Device = $HostScsiLun.CanonicalName
			If ($Device -Like "naa.6000097*" -and $Device.Length -eq 36){
				$row.ArraySerial = $Device.Substring(12,12)
				$DeviceStr = $Device.ToCharArray()
				$LunHex = "_"																		# Add a preceeding '_' to Prevent Excel from mis-interpereting value
				$LunHex += [char][Convert]::ToInt32("$($DeviceStr[28])$($DeviceStr[29])", 16)
				$LunHex += [char][Convert]::ToInt32("$($DeviceStr[30])$($DeviceStr[31])", 16)
				$LunHex += [char][Convert]::ToInt32("$($DeviceStr[32])$($DeviceStr[33])", 16)
				$LunHex += [char][Convert]::ToInt32("$($DeviceStr[34])$($DeviceStr[35])", 16)
				$row.LunHexID = $LunHex
			}
			if ($LunSize/1GB -lt "1"){
				$row.LunSize = "$([math]::Round($LunSize/1MB,0))" + " MB"
			}elseif ($LunSize/1GB -lt "1000"){
				$row.LunSize = "$([math]::Round($LunSize/1GB,0))" + " GB"
			}elseif ($LunSize/1GB -gt "1000"){
				$row.LunSize = "$([math]::Round($LunSize/1TB,0))" + " TB"
			}

			If ($DSHashTable[$NaaId].Mounted -eq "True"){
				If ($DSHashTable[$NaaId].DSName -ne $null){
					$row.DSname = $DSHashTable[$NaaId].DSName
				}else{
					$row.DSName = "NOT a DS, DS NOT Mounted, DS Name NOT Found or RDM"
				}
			}else{
				$row.DSName = "NOT a DS, DS NOT Mounted, DS Name NOT Found or RDM"
			}
			$row.LunID = $LunID
			$row.DSCapacityGB = $DSHashTable[$NaaId].Capacity
			$LunPathStatesA = ($LunPaths.Path | %{$_.State} | ?{$_ -eq "active"}).Count
			$LunPathStatesD = ($LunPaths.Path | %{$_.State} | ?{$_ -eq "dead"}).Count
			$row.State = "Active " + $LunPathStatesA + "|" + "Dead " + $LunPathStatesD
			$row.LunPathSATP = $LunPathSATP					# This could also be $row.LunPathSATP = $LunPaths.StorageArrayTypePolicy.Policy ?????
			Switch -wildcard ($LunPaths.Policy.Policy){
				"*_FIXED" {$Policy = "Fixed"}
				"*_MRU" {$Policy = "MostRecentlyUsed"}
				"*_RR" {$Policy = "RoundRobin"}
					Default{$Policy = "Unknown"}
			}
			$row.Policy = $Policy
			If($RRIOps){
#				$row.RRIOpsSetting = $RRIOps.PathSelectionPolicyDeviceConfig.Substring(11,9)	# Get just the 'iops' value, varies due to length
				$Var = $RRIOps.PathSelectionPolicyDeviceConfig -Split ','						# Break up string
				$row.RRIOpsSetting = $Var[1]													# Get the second line from above, i.e. iops=x
			}else{$row.RRIOpsSetting = "NA"}
			If($HostScsiLun.DevicePath -eq " " -and $HostScsiLun.OperationalState -eq "off"){
				$row.DeviceOpState = "Detached"
			}else{
##			$row.DeviceOpState = $HostScsiLun | Select -ExpandProperty OperationalState
			$row.DeviceOpState = [string]::Join(',',($HostScsiLun | Select-Object -ExpandProperty OperationalState))
			}
			$row.QueueDepth = $HostScsiLun.QueueDepth
			$row.Uuid = $DSHashTable[$NaaId].Uuid
##			$row.PathName = [string]::Join(',',$PathNames)
#
			$row.ATSVMFSHB = $ATSVMFSHeartBeat.Value
			$Report += $row
		} # End foreach Lun
	} # End foreach VMHost
	Disconnect-VIServer $vCenter -Confirm:$false
} # End foreach vCenter
#$Report | Out-GridView											# Display results to screen
$Report | Export-Csv $Filename -NoTypeInformation				# Create CSV file with results
#
Disconnect-VIServer * -Confirm:$false
#
