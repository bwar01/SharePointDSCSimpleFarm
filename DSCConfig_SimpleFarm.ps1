#***************************************************************************************
# This Sample Code is provided for the purpose of illustration only and is not intended to be used in a production environment.  
# THIS SAMPLE CODE AND ANY RELATED INFORMATION ARE PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED OR IMPLIED, INCLUDING BUT NOT LIMITED 
# TO THE IMPLIED WARRANTIES OF MERCHANTABILITY AND/OR FITNESS for A PARTICULAR PURPOSE.  We grant You a nonexclusive, royalty-free right to use and modify 
# the Sample Code and to reproduce and distribute the object code form of the Sample Code, provided that You agree: (i) to not use Our name, logo, or 
# trademarks to market Your software product in which the Sample Code is embedded; (ii) to include a valid copyright notice on Your software product in 
# which the Sample Code is embedded; and (iii) to indemnify, hold harmless, and defend Us and Our suppliers from and against any claims or lawsuits, 
# including attorneys fees, that arise or result from the use or distribution of the Sample Code.
#
#
# -Run this script as a local server Administrator
# -Run this script from elevaed prompt
# 
# Don't forget to: Set-ExecutionPolicy RemoteSigned
#
# Written by Chris Weaver (christwe@microsoft.com) and Charles Teague (charlest@microsoft.com)
#
#****************************************************************************************

Configuration SharePointServer
{
    param (
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [PSCredential] $FarmAccount,
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [PSCredential] $SPSetupAccount,
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [PSCredential] $WebPoolManagedAccount,
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [PSCredential] $ServicePoolManagedAccount,
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [PSCredential] $ContentAccessAccount,
        [Parameter(Mandatory=$false)] $UPASyncConnectAccounts,
        [Parameter(Mandatory=$true)] [ValidateNotNullorEmpty()] [PSCredential] $PassPhrase
    )

    Import-DscResource -ModuleName xPSDesiredStateConfiguration
    Import-DscResource -ModuleName PSDesiredStateConfiguration
    Import-DscResource -ModuleName SharePointDSC
    Import-DscResource -ModuleName xWebAdministration
    Import-DscResource -ModuleName xCredSSP
    Import-DSCResource -ModuleName xSystemSecurity
   # Import-DSCResource -ModuleName xPendingReboot

    node $AllNodes.NodeName
    {
        #**********************************************************
        # Client Server configuration
        #
        # This section of the configuration includes details of the
        # server level configuration, such as disks, registry
        # settings etc.
        #********************************************************** 
        


        #**********************************************************
        # 12/7/16 - Adds feature to each Client server
        #
            WindowsFeature WebAdministration 
             { 
                 Ensure = 'Present'
                 Name   = 'Web-Mgmt-Tools'             
             }
        #
        #********************************************************** 

         

        xCredSSP CredSSPServer { Ensure = "Present"; Role = "Server" } 
        xCredSSP CredSSPClient { Ensure = "Present"; Role = "Client"; DelegateComputers = "*.$($ConfigurationData.NonNodeData.DomainDetails.DomainName)"}

        $FarmInstallTask = "[xCredSSP]CredSSPClient"

        File LocalScratchFolder 
        {
            Type = 'Directory'
            DestinationPath = $ConfigurationData.NonNodeData.DSCConfig.DSCLocalFolder
            Ensure = "Present"
        }

        # Create folders on each server
        $ConfigurationData.NonNodeData.CreateFolders | ForEach {
            $Name = $_.Path
            $Name = ($Name.Split("\"))[1]
            File $Name
            {
                Type = 'Directory'
                DestinationPath = $_.Path
                Ensure = "Present"
            }
        }

       if ($Node.DisableIISLoopbackCheck -eq $true) 
        {
            Registry DisableLoopBackCheck 
            {
                Ensure = "Present"
                Key = "HKLM:\System\CurrentControlSet\Control\Lsa"
                ValueName = "DisableLoopbackCheck"
                ValueData = "1"
                ValueType = "Dword"
            }

            $FarmInstallTask = "[Registry]DisableLoopBackCheck"
        }

# Disable SSL3 and TLS based on version of SharePoint
# https://thesharepointfarm.com/2016/04/enabling-tls-1-2-support-sharepoint-server-2016/
# https://support.microsoft.com/en-us/help/3140245/update-to-enable-tls-1-1-and-tls-1-2-as-a-default-secure-protocols-in
        #**********************************************************
        # IIS clean up
        #
        # This section removes all default sites and application
        # pools from IIS as they are not required
        #**********************************************************

        xWebAppPool RemoveDotNet2Pool         { Name = ".NET v2.0";            Ensure = "Absent"; DependsOn = $FarmInstallTask;}
        xWebAppPool RemoveDotNet2ClassicPool  { Name = ".NET v2.0 Classic";    Ensure = "Absent"; DependsOn = $FarmInstallTask;}
        xWebAppPool RemoveDotNet45Pool        { Name = ".NET v4.5";            Ensure = "Absent"; DependsOn = $FarmInstallTask;}
        xWebAppPool RemoveDotNet45ClassicPool { Name = ".NET v4.5 Classic";    Ensure = "Absent"; DependsOn = $FarmInstallTask;}
        xWebAppPool RemoveClassicDotNetPool   { Name = "Classic .NET AppPool"; Ensure = "Absent"; DependsOn = $FarmInstallTask;}
        xWebAppPool RemoveDefaultAppPool      { Name = "DefaultAppPool";       Ensure = "Absent"; DependsOn = $FarmInstallTask;}
        xWebSite    RemoveDefaultWebSite      { Name = "Default Web Site";     Ensure = "Absent"; PhysicalPath = "C:\inetpub\wwwroot"; DependsOn = $FarmInstallTask;}

        #**********************************************************
        # SharePoint Prerequisites 
        #
        # This section ensure that the Pre-requisites
        # have been installed
        #**********************************************************
     
        if ($Node.InstallPrereqs) 
        {                
            If ($ConfigurationData.NonNodeData.SharePoint.Installation.PrereqInstallMode -eq $false)
            {
                if($ConfigurationData.NonNodeData.SharePoint.Version -eq 2016)
                {
            	    SPInstallPrereqs InstallPrereqs
            	    {
                	    PsDscRunAsCredential = $SPSetupAccount
                	    InstallerPath = (Join-Path $ConfigurationData.NonNodeData.SharePoint.Installation.BinaryDir "\Prerequisiteinstaller.exe")
                	    OnlineMode = $false
                	    Ensure = "Present"
					
					    SQLNCLI 			= (Join-Path $ConfigurationData.NonNodeData.SharePoint.Installation.PrereqInstallerPath "\sqlncli.msi")
					    Sync 				= (Join-Path $ConfigurationData.NonNodeData.SharePoint.Installation.PrereqInstallerPath "\Synchronization.msi")
					    AppFabric 			= (Join-Path $ConfigurationData.NonNodeData.SharePoint.Installation.PrereqInstallerPath "\WindowsServerAppFabricSetup_x64.exe")
					    IDFX11 				= (Join-Path $ConfigurationData.NonNodeData.SharePoint.Installation.PrereqInstallerPath "\MicrosoftIdentityExtensions-64.msi")
					    MSIPCClient 		= (Join-Path $ConfigurationData.NonNodeData.SharePoint.Installation.PrereqInstallerPath "\setup_msipc_x64.exe")
					    KB3092423 			= (Join-Path $ConfigurationData.NonNodeData.SharePoint.Installation.PrereqInstallerPath "\AppFabric-KB3092423-x64-ENU.exe")
					    WCFDataServices56 	= (Join-Path $ConfigurationData.NonNodeData.SharePoint.Installation.PrereqInstallerPath "\WcfDataServices56.exe")
					    MSVCRT11			= (Join-Path $ConfigurationData.NonNodeData.SharePoint.Installation.PrereqInstallerPath "\vc_redist.x64.exe")
					    MSVCRT14			= (Join-Path $ConfigurationData.NonNodeData.SharePoint.Installation.PrereqInstallerPath "\vcredist_x64.exe")
					    ODBC				= (Join-Path $ConfigurationData.NonNodeData.SharePoint.Installation.PrereqInstallerPath "\msodbcsql.msi")
					    DOTNETFX			= (Join-Path $ConfigurationData.NonNodeData.SharePoint.Installation.PrereqInstallerPath "\NDP46-KB3045557-x86-x64-AllOS-ENU.exe")
				    }
                }
			}else
			{
				SPInstallPrereqs InstallPrereqs
            	{
                	PsDscRunAsCredential = $SPSetupAccount
                	InstallerPath = (Join-Path $ConfigurationData.NonNodeData.SharePoint.Installation.BinaryDir "\Prerequisiteinstaller.exe")
                	OnlineMode = $true
                	Ensure = "Present"
            	}
			}

            $FarmInstallTask = "[SPInstallPrereqs]InstallPrereqs"
        }
        
        #**********************************************************
        # SharePoint Binaries 
        #
        # This section ensure that the SharePoint Binaries
        # have been installed
        #**********************************************************
                   
        if ($Node.InstallSharePoint) 
        {
            SPInstall InstallSP2016
            {
                PsDscRunAsCredential = $SPSetupAccount
                ProductKey           = $ConfigurationData.NonNodeData.SharePoint.installation.InstallKey
                BinaryDir            = $ConfigurationData.NonNodeData.SharePoint.installation.BinaryDir
                Ensure               = "Present"
                DependsOn            = $FarmInstallTask
            }
            $FarmInstallTask = "[SPInstall]InstallSP2016"
        }
<#
        if ($node.SSRS) 
        {
            Package SSRSaddinInstall
            {
                PsDscRunAsCredential = $SPSetupAccount
                Path                 = $ConfigurationData.NonNodeData.SSRS.Installation.Binary
                ProductId            = "C3AF130F-8B2E-4D55-8AD1-F156F7C975E8"  
                Name                 = "Microsoft SQL Server 2014 RS Add-in for SharePoint"
                Ensure               = "Present"
                DependsOn            = $FarmInstallTask
            }
        }Else
        {
            Package SSRSaddinInstall
            {
                PsDscRunAsCredential = $SPSetupAccount
                Path                 = $ConfigurationData.NonNodeData.SSRS.Installation.Binary
                ProductId            = "C3AF130F-8B2E-4D55-8AD1-F156F7C975E8"
                Name                 = "Microsoft SQL Server 2014 RS Add-in for SharePoint"
                Ensure               = "Absent"
                DependsOn            = $FarmInstallTask
            }
        }
#>

        #**********************************************************
        # Basic farm
        #
        # This section creates the new SharePoint farm object, and
        # provisions generic services and components used by the
        # whole farm
        #**********************************************************

        # Determine the first app server and let it create the farm, all other servers will join that afterwards
        $FirstAppServer = ($AllNodes | where {$_.FirstServer -eq $true} | Select-Object -First 1).NodeName #Changed 3/2/17

        if ($Node.NodeName -eq $FirstAppServer) 
        {
            #Need to make sure SharePoint is installed to all servers before creating farm
            $waitnodes = ($AllNodes | Where-Object { $_.NodeName -ne $Node.NodeName -and $_.NodeName -ne $FirstAppServer -and $_.NodeName -ne '*' }).NodeName
            if($waitnodes.count -gt 1)
            {
                WaitForAll InstallSharePointtoAllServers
                {
                    ResourceName         = $FarmInstallTask
                    NodeName             = $waitnodes
                    RetryIntervalSec     = 30
                    RetryCount           = 5
                    PsDscRunAsCredential = $SPSetupAccount
                }

                #Creates the Farm on the First Application Server
                SPFarm CreateSPFarm
                {
                    Ensure                   = "Present"
                    DatabaseServer           = $ConfigurationData.NonNodeData.SQLServer.FarmDatabaseServer
                    FarmConfigDatabaseName   = $ConfigurationData.NonNodeData.SharePoint.Farm.ConfigurationDatabase
                    Passphrase               = $PassPhrase
                    FarmAccount              = $FarmAccount
                    PsDscRunAsCredential     = $SPSetupAccount
                    AdminContentDatabaseName = $ConfigurationData.NonNodeData.SharePoint.Farm.AdminContentDatabase
                    CentralAdministrationPort = $ConfigurationData.NonNodeData.SharePoint.Farm.CentralAdminPort
                    ServerRole               = $Node.MinRole
                    RunCentralAdmin          = $Node.CentralAdminHost
                    CentralAdministrationAuth = $ConfigurationData.NonNodeData.SharePoint.Farm.CentralAdminAuth
                    DependsOn                = "[WaitForAll]InstallSharePointtoAllServers"
                }
            }Else
            {
                #if install is single server need to make sure it has correct minrole
                if($Node.MinRole -ne "SingleServer" -or $Node.MinRole -ne "SingleServerFarm")
                {
                    $MinRole = "SingleServerFarm"
                }Else
                {
                    $MinRole = "SingleServerFarm"
                }
                #Creates the Farm on the First Application Server
                SPFarm CreateSPFarm
                {
                    Ensure                   = "Present"
                    DatabaseServer           = $ConfigurationData.NonNodeData.SQLServer.FarmDatabaseServer
                    FarmConfigDatabaseName   = $ConfigurationData.NonNodeData.SharePoint.Farm.ConfigurationDatabase
                    Passphrase               = $PassPhrase
                    FarmAccount              = $FarmAccount
                    PsDscRunAsCredential     = $SPSetupAccount
                    AdminContentDatabaseName = $ConfigurationData.NonNodeData.SharePoint.Farm.AdminContentDatabase
                    CentralAdministrationPort = $ConfigurationData.NonNodeData.SharePoint.Farm.CentralAdminPort
                    ServerRole               = $MinRole
                    RunCentralAdmin          = $Node.CentralAdminHost
                    CentralAdministrationAuth = $ConfigurationData.NonNodeData.SharePoint.Farm.CentralAdminAuth
                }
            }

            

        }Else 
        {
            #Waits for the Farm to be created before the Joining the Server to the Farm
            WaitForAll WaitForFarmToExist
            {
                ResourceName         = $FarmInstallTask    #"[SPFarm]CreateSPFarm"
                NodeName             = $FirstAppServer
                RetryIntervalSec     = 30
                RetryCount           = 5
                PsDscRunAsCredential = $SPSetupAccount
            }

            #Joins the server to the Farm
            SPFarm JoinSPFarm
            {
                Ensure                   = "Present"
                DatabaseServer           = $ConfigurationData.NonNodeData.SQLServer.FarmDatabaseServer
                FarmConfigDatabaseName   = $ConfigurationData.NonNodeData.SharePoint.Farm.ConfigurationDatabase
                Passphrase               = $PassPhrase #$ConfigurationData.NonNodeData.SharePoint.Farm.Passphrase
                FarmAccount              = $FarmAccount
                PsDscRunAsCredential     = $SPSetupAccount
                AdminContentDatabaseName = $ConfigurationData.NonNodeData.SharePoint.Farm.AdminContentDatabase
                CentralAdministrationPort = $ConfigurationData.NonNodeData.SharePoint.Farm.CentralAdminPort
                ServerRole               = $Node.MinRole
                RunCentralAdmin          = $Node.CentralAdminHost
                CentralAdministrationAuth = $ConfigurationData.NonNodeData.SharePoint.Farm.CentralAdminAuth
                DependsOn                = "[WaitForAll]WaitForFarmToExist"
            }
        }

        #**********************************************************
        # Basic farm Config
        #
        # This section provisions generic services and components used by the
        # whole farm
        #**********************************************************

        # Apply farm wide configuration and logical components only on the first server        
        if ($Node.NodeName -eq $FirstAppServer) 
        {
            
            #Add farm account to list so we don't remove from Farm group
            $FarmAdmin = $ConfigurationData.NonNodeData.SharePoint.Farm.FarmAdmins
            $FarmAdmin += $ConfigurationData.NonNodeData.SharePoint.ServiceAccounts.FarmAccount
            $FarmAdmin += $ConfigurationData.NonNodeData.SharePoint.ServiceAccounts.SetupAccount
            SPFarmAdministrators LocalFarmAdmins
            {
                Name                 = "Farm Administrators"
                Members              = $FarmAdmin
                DependsOn            = $FarmWaitTask
                PsDscRunAsCredential = $SPSetupAccount
            }

            SPPasswordChangeSettings ManagedAccountPasswordResetSettings  
            {  
                MailAddress                   = $ConfigurationData.NonNodeData.SharePoint.ServiceAccounts.ManagedAccountPasswordResetSettings.AdministratorMailAddress
                DaysBeforeExpiry              = $ConfigurationData.NonNodeData.SharePoint.ServiceAccounts.ManagedAccountPasswordResetSettings.SendmessageDaysBeforeExpiry
                PasswordChangeWaitTimeSeconds = $ConfigurationData.NonNodeData.SharePoint.ServiceAccounts.ManagedAccountPasswordResetSettings.PasswordChangeTimeoutinSec
                NumberOfRetries               = $ConfigurationData.NonNodeData.SharePoint.ServiceAccounts.ManagedAccountPasswordResetSettings.PasswordChangeNumberOfRetries
                PsDscRunAsCredential          = $SPSetupAccount
            }

            SPManagedAccount ServicePoolManagedAccount
            {
                AccountName          = $ServicePoolManagedAccount.UserName
                Account              = $ServicePoolManagedAccount
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn            = $FarmWaitTask
            }
            SPManagedAccount WebPoolManagedAccount
            {
                AccountName          = $WebPoolManagedAccount.UserName
                Account              = $WebPoolManagedAccount
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn            = $FarmWaitTask
            }
            SPDiagnosticLoggingSettings ApplyDiagnosticLogSettings
            {
                LogPath                                     = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.Path
                LogSpaceInGB                                = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.MaxSizeGB
                AppAnalyticsAutomaticUploadEnabled          = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.AppAnalyticsAutomaticUploadEnabled
                CustomerExperienceImprovementProgramEnabled = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.CustomerExperienceImprovementProgramEnabled
                DaysToKeepLogs                              = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.DaysToKeep
                DownloadErrorReportingUpdatesEnabled        = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.DownloadErrorReportingUpdatesEnabled
                ErrorReportingAutomaticUploadEnabled        = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.ErrorReportingAutomaticUploadEnabled
                ErrorReportingEnabled                       = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.ErrorReportingEnabled
                EventLogFloodProtectionEnabled              = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.EventLogFloodProtectionEnabled
                EventLogFloodProtectionNotifyInterval       = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.EventLogFloodProtectionNotifyInterval 
                EventLogFloodProtectionQuietPeriod          = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.EventLogFloodProtectionQuietPeriod 
                EventLogFloodProtectionThreshold            = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.EventLogFloodProtectionThreshold 
                EventLogFloodProtectionTriggerPeriod        = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.EventLogFloodProtectionTriggerPeriod
                LogCutInterval                              = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.LogCutInterval 
                LogMaxDiskSpaceUsageEnabled                 = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.LogMaxDiskSpaceUsageEnabled
                ScriptErrorReportingDelay                   = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.ScriptErrorReportingDelay 
                ScriptErrorReportingEnabled                 = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.ScriptErrorReportingEnabled 
                ScriptErrorReportingRequireAuth             = $ConfigurationData.NonNodeData.SharePoint.DiagnosticLogs.ScriptErrorReportingRequireAuth  
                PsDscRunAsCredential                        = $SPSetupAccount
                DependsOn                                   = $FarmWaitTask
            }

            SPStateServiceApp StateServiceApp
            {
                Name                 = $ConfigurationData.NonNodeData.SharePoint.StateService.Name
                DatabaseName         = $ConfigurationData.NonNodeData.SharePoint.StateService.DatabaseName
                DatabaseServer       = $ConfigurationData.NonNodeData.SQLServer.ServiceAppDatabaseServer
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn            = $FarmWaitTask
            }

            Script SetInboundMailSettings
            {
                GetScript = {
                    Return @{Result = [string]$(Invoke-SPDscCommand -ScriptBlock {Get-SPServiceInstance | where {$_.TypeName -eq "Microsoft SharePoint Foundation Incoming E-Mail"} | Select-Object -First 1})}
                }
                SetScript = {
                    $Enabled = $ConfigurationData.NonNodeData.SharePoint.InboundEmail.Enable
                    $EmailDomain = $ConfigurationData.NonNodeData.SharePoint.InboundEmail.EmailDomain
                    Invoke-SPDscCommand -ScriptBlock {
                        $svcinstance = Get-SPServiceInstance | where {($_.TypeName -eq "Microsoft SharePoint Foundation Incoming E-Mail") -and ($_.Status -eq "Online")}
                        #$svcinstance = Get-SPServiceInstance | where {$_.TypeName -eq "Microsoft SharePoint Foundation Incoming E-Mail"} | Select-Object -First 1
                        $svcinstance.Service.Enabled = $args[0]
                        $svcinstance.Service.UseAutomaticSettings = $True 
                        $svcinstance.Service.ServerDisplayAddress = $args[1]
                        $svcinstance.Service.Update()
                    } -Arguments $Enabled $EmailDomain
                }
                TestScript = {
                    Invoke-SPDscCommand -ScriptBlock {
                        if(($svcinstance = Get-SPServiceInstance | where {($_.TypeName -eq "Microsoft SharePoint Foundation Incoming E-Mail") -and ($_.Status -eq "Online")}).Service.Enabled)
                        {
                            Return $true
                        }Else
                        {
                            Return $false
                        }
                    }
                }
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn = $FarmWaitTask
            }
        }


        #*******************************************
        # Starting services if not using MINROle in SP2016 or if configuring SP2013
        #**********************************************************
        if ($Node.MinRole -eq 'Custom') 
        {
            #**********************************************************
            # Common Services across all nodes
            #**********************************************************
            SPServiceInstance ClaimsToWindowsTokenServiceInstance
            {  
                Name                 = "Claims to Windows Token Service"
                Ensure               = "Present"
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn            = $FarmWaitTask
            }

            $FarmWaitTask = "[SPServiceInstance]ClaimsToWindowsTokenServiceInstance"

            #**********************************************************
            # Distributed cache
            #
            # This section calculates which servers should be running
            # DistributedCache and which servers they depend on
            #**********************************************************

            if ($Node.CustomServices.DistributedCache -eq $true) 
            {
                $AllDCacheNodes = $AllNodes | Where-Object { $_.MinRole -eq 'Custom' -or $_.CustomServices.DistributedCache -eq $true }
                $CurrentDcacheNode = [Array]::IndexOf($AllDCacheNodes, $Node)

                if ($Node.NodeName -ne $FirstAppServer) 
                {
                    # Node is not the first app server so won't have the dependency for the service account
                    WaitForAll WaitForServiceAccount 
                    {
                        ResourceName         = "[SPManagedAccount]ServicePoolManagedAccount"
                        NodeName             = $FirstAppServer
                        RetryIntervalSec     = 30
                        RetryCount           = 5
                        PsDscRunAsCredential = $SPSetupAccount
                        DependsOn            = $FarmWaitTask 
                    }
                    $DCacheWaitFor = "[WaitForAll]WaitForServiceAccount"
                }Else
                {
                    $DCacheWaitFor = "[SPManagedAccount]ServicePoolManagedAccount"
                }

                if ($CurrentDcacheNode -eq 0) 
                {
                    # The first distributed cache node doesn't wait on anything
                    SPDistributedCacheService EnableDistributedCache
                    {
                        Name                 = "AppFabricCachingService"
                        Ensure               = "Present"
                        CacheSizeInMB        = $ConfigurationData.NonNodeData.SharePoint.DCache.CacheSizeInMB
                        ServiceAccount       = $ServicePoolManagedAccount.UserName
                        CreateFirewallRules  = $true
                        ServerProvisionOrder = $AllDCacheNodes.NodeName
                        PsDscRunAsCredential = $SPSetupAccount
                        DependsOn            = @($FarmWaitTask,$DCacheWaitFor)
                    }
                }Else 
                {
                    # All other distributed cache nodes depend on the node previous to it
                    $previousDCacheNode = $AllDCacheNodes[$CurrentDcacheNode - 1]
                    WaitForAll WaitForDCache
                    {
                        ResourceName         = "[SPDistributedCacheService]EnableDistributedCache"
                        NodeName             = $previousDCacheNode.NodeName
                        RetryIntervalSec     = 60
                        RetryCount           = 60
                        PsDscRunAsCredential = $SPSetupAccount
                        DependsOn            = $FarmWaitTask
                    }
                    SPDistributedCacheService EnableDistributedCache
                    {
                        Name                 = "AppFabricCachingService"
                        Ensure               = "Present"
                        CacheSizeInMB        = $ConfigurationData.NonNodeData.SharePoint.DCache.CacheSizeInMB
                        ServiceAccount       = $ServicePoolManagedAccount.UserName
                        CreateFirewallRules  = $true
                        ServerProvisionOrder = $AllDCacheNodes.NodeName
                        PsDscRunAsCredential = $SPSetupAccount
                        DependsOn            = "[WaitForAll]WaitForDCache"
                    }
                }
            }
            If ($Node.CustomServices.AppManagement -eq $true) 
            {
                SPServiceInstance AppManagementService 
                {
                    Name                 = "App Management Service"
                    Ensure               = "Present"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }Else
            {
                SPServiceInstance AppManagementService 
                {
                    Name                 = "App Management Service"
                    Ensure               = "Absent"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }
            If ($Node.CustomServices.BCS -eq $true) 
            {
                SPServiceInstance BCSServiceInstance
                {  
                    Name                 = "Business Data Connectivity Service"
                    Ensure               = "Present"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }Else
            {
                SPServiceInstance BCSServiceInstance
                {  
                    Name                 = "Business Data Connectivity Service"
                    Ensure               = "Absent"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }
            If ($Node.CustomServices.SubscriptionSettings -eq $true) 
            {
                SPServiceInstance SubscriptionSettingsService
                {  
                    Name                 = "Microsoft SharePoint Foundation Subscription Settings Service"
                    Ensure               = "Present"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }Else
            {
                SPServiceInstance SubscriptionSettingsService
                {  
                    Name                 = "Microsoft SharePoint Foundation Subscription Settings Service"
                    Ensure               = "Absent"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }
            If ($Node.CustomServices.SecureStore -eq $true) 
            {
                 SPServiceInstance SecureStoreService
                {  
                    Name                 = "Secure Store Service"
                    Ensure               = "Present"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }Else
            {
                SPServiceInstance SecureStoreService
                {  
                    Name                 = "Secure Store Service"
                    Ensure               = "Absent"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }
            If ($Node.CustomServices.UserProfile -eq $true) 
            {
                SPServiceInstance UserProfileService
                {  
                    Name                 = "User Profile Service"
                    Ensure               = "Present"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }Else
            {
                SPServiceInstance UserProfileService
                {  
                    Name                 = "User Profile Service"
                    Ensure               = "Absent"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }
            If ($Node.CustomServices.WorkFlowTimer -eq $true) 
            {
                SPServiceInstance WorkflowTimerService 
                {
                    Name                 = "Microsoft SharePoint Foundation Workflow Timer Service"
                    Ensure               = "Present"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }Else
            {
                SPServiceInstance WorkflowTimerService 
                {
                    Name                 = "Microsoft SharePoint Foundation Workflow Timer Service"
                    Ensure               = "Absent"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }
            if ($Node.CustomServices.WebFrontEnd -eq $true) 
            {
                SPServiceInstance WebApplicationService
                {  
                    Name                 = "Microsoft SharePoint Foundation Web Application"
                    Ensure               = "Present"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }Else
            {
                SPServiceInstance WebApplicationService
                {  
                    Name                 = "Microsoft SharePoint Foundation Web Application"
                    Ensure               = "Absent"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }
            if ($Node.CustomServices.ManagedMetadata -eq $true) 
            {
                SPServiceInstance ManagedMetadataServiceInstance
                {  
                    Name                 = "Managed Metadata Web Service"
                    Ensure               = "Present"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }Else
            {
                SPServiceInstance ManagedMetadataServiceInstance
                {  
                    Name                 = "Managed Metadata Web Service"
                    Ensure               = "Absent"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }
            if ($Node.CustomServices.VisioGraphics -eq $true) 
            {
                SPServiceInstance VisioGraphicsService
                {  
                    Name                 = "Visio Graphics Service"
                    Ensure               = "Present"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }Else
            {
                SPServiceInstance VisioGraphicsService
                {  
                    Name                 = "Visio Graphics Service"
                    Ensure               = "Absent"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }
            if ($Node.CustomServices.Search -eq $true) 
            {
                SPServiceInstance SearchService 
                {  
                    Name                 = "SharePoint Server Search"
                    Ensure               = "Present"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }Else
            {
                SPServiceInstance SearchService 
                {  
                    Name                 = "SharePoint Server Search"
                    Ensure               = "Absent"
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmWaitTask
                }
            }      
        }


        #**********************************************************
        # Service applications
        #
        # This section creates service applications and required
        # dependencies
        #**********************************************************
        if ($Node.NodeName -eq $FirstAppServer) 
        {
            SPServiceAppPool MainServiceAppPool
            {
                Name                 = $ConfigurationData.NonNodeData.SharePoint.Services.ApplicationPoolName
                ServiceAccount       = $ServicePoolManagedAccount.UserName
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn            = $FarmWaitTask
            }

            SPSecureStoreServiceApp SecureStoreServiceApp
            {
                Name                  = $ConfigurationData.NonNodeData.SharePoint.SecureStoreService.Name
                ApplicationPool       = $ConfigurationData.NonNodeData.SharePoint.Services.ApplicationPoolName
                AuditingEnabled       = $ConfigurationData.NonNodeData.SharePoint.SecureStoreService.AuditingEnabled
                AuditlogMaxSize       = $ConfigurationData.NonNodeData.SharePoint.SecureStoreService.AuditLogMaxSize
                DatabaseName          = $ConfigurationData.NonNodeData.SharePoint.SecureStoreService.DatabaseName
                DatabaseServer        = $ConfigurationData.NonNodeData.SQLServer.ServiceAppDatabaseServer
                PsDscRunAsCredential  = $SPSetupAccount
                DependsOn             = "[SPServiceAppPool]MainServiceAppPool"
            }

            SPManagedMetaDataServiceApp ManagedMetadataServiceApp
            {  
                Name                 = $ConfigurationData.NonNodeData.SharePoint.ManagedMetadataService.Name
                ApplicationPool      = $ConfigurationData.NonNodeData.SharePoint.Services.ApplicationPoolName
                DatabaseName         = $ConfigurationData.NonNodeData.SharePoint.ManagedMetadataService.DatabaseName
                DatabaseServer       = $ConfigurationData.NonNodeData.SQLServer.ServiceAppDatabaseServer
                #TermStoreAdministrators = $ConfigurationData.NonNodeData.SharePoint.ManagedMetadataService.TermStoreAdministrators
                #ContentTypeHubUrl = ""
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn            = "[SPServiceAppPool]MainServiceAppPool"
            }

            SPBCSServiceApp BCSServiceApp
            {
                Name                  = $ConfigurationData.NonNodeData.SharePoint.BCSService.Name
                ApplicationPool       = $ConfigurationData.NonNodeData.SharePoint.Services.ApplicationPoolName
                DatabaseName          = $ConfigurationData.NonNodeData.SharePoint.BCSService.DatabaseName
                DatabaseServer        = $ConfigurationData.NonNodeData.SQLServer.ServiceAppDatabaseServer
                PsDscRunAsCredential  = $SPSetupAccount
                DependsOn             = @('[SPServiceAppPool]MainServiceAppPool', '[SPSecureStoreServiceApp]SecureStoreServiceApp')
            }

            SPAppManagementServiceApp AppManagementServiceApp
            {
                Name                  = $ConfigurationData.NonNodeData.SharePoint.AppManagementService.Name
                DatabaseName          = $ConfigurationData.NonNodeData.SharePoint.AppManagementService.DatabaseName
                DatabaseServer        = $ConfigurationData.NonNodeData.SQLServer.ServiceAppDatabaseServer
                ApplicationPool       = $ConfigurationData.NonNodeData.SharePoint.Services.ApplicationPoolName
                PsDscRunAsCredential  = $SPSetupAccount
                DependsOn             = "[SPServiceAppPool]MainServiceAppPool"
            }

            SPSubscriptionSettingsServiceApp SubscriptionSettingsServiceApp
            {
                Name                  = $ConfigurationData.NonNodeData.SharePoint.SubscriptionSettingsService.Name
                DatabaseName          = $ConfigurationData.NonNodeData.SharePoint.SubscriptionSettingsService.DatabaseName
                DatabaseServer        = $ConfigurationData.NonNodeData.SQLServer.ServiceAppDatabaseServer
                ApplicationPool       = $ConfigurationData.NonNodeData.SharePoint.Services.ApplicationPoolName
                PsDscRunAsCredential  = $SPSetupAccount
                DependsOn             = "[SPServiceAppPool]MainServiceAppPool"
            }

            SPVisioServiceApp VisioServiceApp
            {
                Name                  = $ConfigurationData.NonNodeData.SharePoint.VisioService.Name
                ApplicationPool       = $ConfigurationData.NonNodeData.SharePoint.Services.ApplicationPoolName
                PsDscRunAsCredential  = $SPSetupAccount
                DependsOn             = "[SPServiceAppPool]MainServiceAppPool"
            }

            #**********************************************************
            # Web applications
            #
            # This section creates the web applications in the 
            # SharePoint farm, as well as managed paths and other web
            # application settings
            #**********************************************************


            foreach($webApp in $ConfigurationData.NonNodeData.SharePoint.WebApplications) {
                $webAppInternalName = $webApp.Name.Replace(" ", "")

# Add ability to create multiple bindings for web applications
                #Create the Web Application
                SPWebApplication $webAppInternalName
                {
                    Ensure                 = "Present"
                    UseClassic             = $webApp.UseClassic
                    Name                   = $webApp.Name
                    ApplicationPool        = $webApp.AppPool
                    ApplicationPoolAccount = $webApp.AppPoolAccount
                    AllowAnonymous         = $webApp.Anonymous
                   # UseSSL                 = $webApp.UseSSL
                   # AuthenticationMethod   = $webApp.Authentication
                    DatabaseName           = $webApp.DatabaseName
                    DatabaseServer         = $ConfigurationData.NonNodeData.SQLServer.ContentDatabaseServer
                    Url                    = $webApp.Url
                    HostHeader             = $WebApp.BindingHostHeader   
                    Port                   = $WebApp.WebPort
                    PsDscRunAsCredential   = $SPSetupAccount
                    DependsOn              = "[SPManagedAccount]WebPoolManagedAccount"
                }
                
                #Web Application Settings
                $webSettingsName = $webAppInternalName + "WebAppGeneralSettings"
                SPWebAppGeneralSettings $webSettingsName
                {
                    Url = $webApp.Url
                    MaximumUploadSize = $webApp.MaximumUploadSize
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn = "[SPWebApplication]$webAppInternalName"
                }

                # If using host named site collections, create the empty path based site here
                if ($webApp.UseHostNamedSiteCollections -eq $true) 
                {          
                    if($WebApp.Port -eq 443)
                    {
                        $Protocol = "HTTPS"
                    }Else
                    {
                        $Protocol = "HTTP"
                    }
                    #create an http binding with no hostheader
                    xWebSite "$WebAppInternalName"         
                    {
                        Ensure = "Present"
                        Name = $WebApp.Name
                        State = "Started"

                        BindingInfo = MSFT_xWebBindingInformation
                        {
                            Protocol = $Protocol
                            IPAddress = "*"
                            Port     = $WebApp.Port   
                        }
                        DependsOn = "[SPWebApplication]$webAppInternalName"
                    }
                <#    $hnscName = $webAppInternalName + "HNSCRootSite"
                    SPSite $hnscName
                    {
                        Url                      = $webApp.Url
                        OwnerAlias               = $SPSetupAccount.Username
                        Name                     = "Root site"
                        Template                 = "STS#0"
                        PsDscRunAsCredential     = $SPSetupAccount
                        DependsOn                = "[SPWebApplication]$webAppInternalName"
                    }
                    #>
                }

                #Create the managed paths
                foreach($managedPath in $webApp.ManagedPaths) {
                    SPManagedPath "$($webAppInternalName)Path$($managedPath.Path)" 
                    {
                        WebAppUrl            = $webApp.Url
                        PsDscRunAsCredential = $SPSetupAccount
                        RelativeUrl          = $managedPath.Path
                        Explicit             = $managedPath.Explicit
                        HostHeader           = $false #$webApp.UseHostNamedSiteCollections
                        DependsOn            = "[SPWebApplication]$webAppInternalName"
                    }
                }
            
                #Set the CachAccounts for the web application
                SPCacheAccounts "$($webAppInternalName)CacheAccounts"
                {
                    WebAppUrl              = $webApp.Url
                    SuperUserAlias         = $webApp.SuperUser
                    SuperReaderAlias       = $webApp.SuperReader
                    PsDscRunAsCredential   = $SPSetupAccount
                    DependsOn              = "[SPWebApplication]$webAppInternalName"
                }

                #Ensure we have the Content Databases created foreach Site Collection
                #$scContentDatabases = ($webApp.Sitecollections).ContentDatabase | Sort-Object | Get-Unique
                $scWaitTask = @("[SPWebApplication]$webAppInternalName")
                
                #Create the Site Collections
                foreach($siteCollection in $webApp.SiteCollections) {
                    $internalSiteName = "$($webAppInternalName)Site$($siteCollection.Name.Replace(' ', ''))"
                    if ($webApp.UseHostNamedSiteCollections -eq $true -and $siteCollection.HostNamedSiteCollection -eq $true) 
                    {
                        SPSite $internalSiteName
                        {
                            Url                      = $siteCollection.Url
                            OwnerAlias               = $siteCollection.Owner
                            HostHeaderWebApplication = $webApp.Url
                            Name                     = $siteCollection.Name
                            Template                 = $siteCollection.Template
                            ContentDatabase          = $siteCollection.ContentDatabase
                            PsDscRunAsCredential     = $SPSetupAccount
                            DependsOn                = $scWaitTask
                        }
                    }Else 
                    {
                        SPSite $internalSiteName
                        {
                            Url                      = $siteCollection.Url
                            OwnerAlias               = $siteCollection.Owner
                            Name                     = $siteCollection.Name
                            Template                 = $siteCollection.Template
                            ContentDatabase          = $siteCollection.Database
                            PsDscRunAsCredential     = $SPSetupAccount
                            DependsOn                = $scWaitTask
                        }
                    }
                }
            }

            foreach($EmailSetting in $ConfigurationData.NonNodeData.SharePoint.OutgoingEmail) {
                $Name = $EmailSetting.WebAppUrl
                SPOutgoingEmailSettings $Name
                {
                    WebAppUrl            = $EmailSetting.WebAppUrl
                    SMTPServer           = $EmailSetting.SMTPServer
                    FromAddress          = $EmailSetting.FromAddress
                    ReplyToAddress       = $EmailSetting.ReplyToAddress
                    CharacterSet         = $EmailSetting.CharacterSet
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $scWaitTask
                }
            }
            SPUserProfileServiceApp UserProfileServiceApp
            {
                Ensure               = "Present"
                NoILMUsed            = $ConfigurationData.NonNodeData.SharePoint.UserProfileService.UseADImport
                ProxyName            = $ConfigurationData.NonNodeData.SharePoint.UserProfileService.ProxyName
                Name                 = $ConfigurationData.NonNodeData.SharePoint.UserProfileService.Name
                ApplicationPool      = $ConfigurationData.NonNodeData.SharePoint.Services.ApplicationPoolName
                MySiteHostLocation   = $ConfigurationData.NonNodeData.SharePoint.UserProfileService.MySiteUrl
                ProfileDBName        = $ConfigurationData.NonNodeData.SharePoint.UserProfileService.ProfileDB
                ProfileDBServer      = $ConfigurationData.NonNodeData.SQLServer.ServiceAppDatabaseServer
                SocialDBName         = $ConfigurationData.NonNodeData.SharePoint.UserProfileService.SocialDB
                SocialDBServer       = $ConfigurationData.NonNodeData.SQLServer.ServiceAppDatabaseServer
                SyncDBName           = $ConfigurationData.NonNodeData.SharePoint.UserProfileService.SyncDB
                SyncDBServer         = $ConfigurationData.NonNodeData.SQLServer.ServiceAppDatabaseServer
                EnableNetbios        = $ConfigurationData.NonNodeData.SharePoint.UserProfileService.NetbiosEnable
               # FarmAccount          = $FarmAccount
                PsDscRunAsCredential = $SPSetupAccount
                DependsOn            = @('[SPServiceAppPool]MainServiceAppPool', '[SPManagedMetaDataServiceApp]ManagedMetadataServiceApp', '[SPManagedAccount]WebPoolManagedAccount')
            }
            if($UPASyncConnectAccounts -or ($UPASyncConnectAccounts).count -gt 0)
            {
                if($ConfigurationData.NonNodeData.SharePoint.Version -eq 2013)
                {
                    foreach($UPASyncConnection in $ConfigurationData.NonNodeData.SharePoint.UserProfileService.UserProfileSyncConnection) {
                        $ConnectionAccountCreds = $UPASyncConnectAccounts | where {$_.UserName -eq $UPASyncConnection.ConnectionUsername}
                        SPUserProfileSyncConnection $UPASyncConnection.Name
                        {
                            UserProfileService = $ConfigurationData.NonNodeData.SharePoint.UserProfileService.Name
                            Forest = $UPASyncConnection.Forest
                            Name = $UPASyncConnection.Name
                            ConnectionCredentials = $ConnectionAccountCreds
                            Server = $UPASyncConnection.Server
                            UseSSL = $UPASyncConnection.UseSSL
                            IncludedOUs = $UPASyncConnection.IncludedOUs
                            ExcludedOUs = $UPASyncConnection.ExcludedOUs
                            Force = $UPASyncConnection.Force
                            ConnectionType = "ActiveDirectory"
                            PsDscRunAsCredential = $SPSetupAccount
                            DependsOn = "[SPUserProfileServiceApp]UserProfileServiceApp"
                        }
                    }
                }
                Else
                {
                }
            }
            ForEach($Item in $ConfigurationData.NonNodeData.FilesandFolders)
            {
                $Name = $Item.Source
                File $Name
                {
                    Ensure = $Item.Ensure
                    Type = $Item.Type
                    Recurse = $Item.Recurse
                    SourcePath = $Item.Source
                    DestinationPath = $Item.Destination
                    Force = $Item.Force
                    MatchSource = $Item.MatchSource
                    Credential = $SPSetupAccount
                    DependsOn = $FarmWaitTask
                }
            }

        }

        $searchNode = ($AllNodes | Where-Object { $_.MinRole -eq 'Search' -or $_.MinRole -eq 'ApplicationWithSearch' -or ($_.MinRole -eq 'Custom' -and $_.CustomServices.Search) -or $_.MinRole -eq 'SingleServer' } | Select-Object -First 1)
        
        if($searchNode -ne $null) 
        {
            $FirstSearchServer = $searchNode.NodeName
            #**********************************************************
            # Search Topology
            #
            # This section creates the Search Topology
            #**********************************************************
            if ($Node.NodeName -eq $FirstSearchServer) 
            {
                #Wait for the managed accounts and
                WaitForAll WaitForMainServiceAppPool
                {
                    ResourceName         = "[SPServiceAppPool]MainServiceAppPool"
                    NodeName             = $FirstAppServer
                    RetryIntervalSec     = 60
                    RetryCount           = 60
                    PsDscRunAsCredential = $SPSetupAccount
                    DependsOn            = $FarmInstallTask
                }

                SPSearchServiceApp SearchServiceApp
                {  
                    Name                  = $ConfigurationData.NonNodeData.SharePoint.Search.Name
                    DatabaseName          = $ConfigurationData.NonNodeData.SharePoint.Search.DatabaseName
                    DatabaseServer        = $ConfigurationData.NonNodeData.SQLServer.ServiceAppDatabaseServer
                    ApplicationPool       = $ConfigurationData.NonNodeData.SharePoint.Services.ApplicationPoolName
                    DefaultContentAccessAccount = $ContentAccessAccount
                    CloudIndex            = $ConfigurationData.NonNodeData.SharePoint.Search.CloudSSA
                    PsDscRunAsCredential  = $SPSetupAccount
                    DependsOn             = "[WaitForAll]WaitForMainServiceAppPool"
                }
                ForEach($SSA in $ConfigurationData.NonNodeData.SharePoint.Search)
                {
                    $SSAName = $SSA.Name
                    SPSearchTopology $SSAName
                    {
                        ServiceAppName          = $SSA.Name
                        Admin                   = $SSA.SearchTopology.Admin
                        Crawler                 = $SSA.SearchTopology.Crawler
                        ContentProcessing       = $SSA.SearchTopology.ContentProcesing
                        AnalyticsProcessing     = $SSA.SearchTopology.AnalyticsProcesing
                        QueryProcessing         = $SSA.SearchTopology.QueryProcesing
                        FirstPartitionDirectory = $SSA.SearchTopology.IndexPartition0Folder
                        IndexPartition          = $SSA.SearchTopology.IndexPartition0
                        PsDscRunAsCredential    = $SPSetupAccount
                        DependsOn               = "[SPSearchServiceApp]SearchServiceApp"
                    }
                    ForEach($Partition in $ConfigurationData.NonNodeData.SharePoint.Search.SearchTopology.IndexPartitions)
                    { 
                        $IndexName = $SSA.Name + "Partition" + $Partition.Index
                        SPSearchIndexPartition $IndexName
                        {
                            Servers              = $Partition.Servers
                            Index                = $Partition.Index
                            RootDirectory        = $Partition.IndexPartitionFolder
                            ServiceAppName       = $SSA.Name
                            PsDscRunAsCredential = $SPSetupAccount
                            DependsOn            = "[SPSearchTopology]$SSAName"
                        }
                    }
                   
             <#       $ConfigurationData.NonNodeData.SharePoint.Search.SearchContentSource | ForEach-Object{
                        if(!($_.IncrementalSchedule))
                        {
                            $Incremental_Schedule = $null
                        }Else
                        {                                                                                                                                        
                            Switch($_.IncrementalSchedule.ScheduleType)
                            {
                                "Daily" {
                                            $Incremental_Schedule = MSFT_SPSearchCrawlSchedule {
                                                ScheduleType = "Daily" 
                                                StartHour = $_.IncrementalSchedule.StartHour
                                                StartMinute = $_.IncrementalSchedule.StartMinute
                                                CrawlScheduleRepeatDuration = $_.IncrementalSchedule.CrawlScheduleRepeatDuration
                                                CrawlScheduleRepeatInterval = $_.IncrementalSchedule.CrawlScheduleRepeatInterval
                                            }
                                        }
                               "Weekly" {
                                            $Incremental_Schedule = MSFT_SPSearchCrawlSchedule {
                                                ScheduleType = "Weekly"
                                                CrawlScheduleDaysofWeek = $_.IncrementalSchedule.CrawlScheduleDaysOfWeek
                                                StartHour = $_.IncrementalSchedule.StartHour
                                                StartMinute = $_.IncrementalSchedule.StartMinute
                                                CrawlScheduleRepeatDuration = $_.IncrementalSchedule.CrawlScheduleRepeatDuration
                                                CrawlScheduleRepeatInterval = $_.IncrementalSchedule.CrawlScheduleRepeatInterval
                                            }
                                        }
                              "Monthly" {
                                            $Incremental_Schedule = MSFT_SPSearchCrawlSchedule {
                                                ScheduleType = "Monthly"
                                                CrawlScheduleMonthsofYear = $_.IncrementalSchedule.CrawlScheduleMonthsofYear
                                                StartHour = $_.IncrementalSchedule.StartHour
                                                StartMinute = $_.IncrementalSchedule.StartMinute
                                                CrawlScheduleRepeatDuration = $_.IncrementalSchedule.CrawlScheduleRepeatDuration
                                                CrawlScheduleRepeatInterval = $_.IncrementalSchedule.CrawlScheduleRepeatInterval
                                            }
                                        }
                            }
                        }
                        if(!($_.FullSchedule))
                        {
                            $Full_Schedule = $null
                        }Else
                        {                                                                                                                                    
                            Switch($_.FullSchedule.ScheduleType)
                            {
                                "Daily" {
                                            $Full_Schedule = MSFT_SPSearchCrawlSchedule {
                                                ScheduleType = "Daily" 
                                                StartHour = $_.FullSchedule.StartHour
                                                StartMinute = $_.FullSchedule.StartMinute
                                                CrawlScheduleRepeatDuration = $_.FullSchedule.CrawlScheduleRepeatDuration
                                                CrawlScheduleRepeatInterval = $_.FullSchedule.CrawlScheduleRepeatInterval
                                            }
                                        }
                               "Weekly" {
                                            $Full_Schedule = MSFT_SPSearchCrawlSchedule {
                                                ScheduleType = "Weekly"
                                                CrawlScheduleDaysOfWeek = $_.FullSchedule.CrawlScheduleDaysOfWeek
                                                StartHour = $_.FullSchedule.StartHour
                                                StartMinute = $_.FullSchedule.StartMinute
                                                CrawlScheduleRepeatDuration = $_.FullSchedule.CrawlScheduleRepeatDuration
                                                CrawlScheduleRepeatInterval = $_.FullSchedule.CrawlScheduleRepeatInterval
                                            }
                                        }
                              "Monthly" {
                                            $Full_Schedule = MSFT_SPSearchCrawlSchedule {
                                                ScheduleType = "Monthly"
                                                CrawlScheduleMonthsofYear = $_.FullSchedule.CrawlScheduleMonthsofYear
                                                StartHour = $_.FullSchedule.StartHour
                                                StartMinute = $_.FullSchedule.StartMinute
                                                CrawlScheduleRepeatDuration = $_.FullSchedule.CrawlScheduleRepeatDuration
                                                CrawlScheduleRepeatInterval = $_.FullSchedule.CrawlScheduleRepeatInterval
                                            }
                                        }
                            }
                        }
                        SPSearchContentSource $_.Name
                        {
                            Name                 = $_.Name
                            ServiceAppName       = $_.ServiceAppName
                            ContentSourceType    = $_.ContentSourceType
                            Addresses            = $_.Addresses
                            CrawlSetting         = $_.CrawlSetting
                            ContinuousCrawl      = $_.ContinuousCrawl
                            IncrementalSchedule  = $Incremental_Schedule
                            FullSchedule         = $Full_Schedule
                            Priority             = $_.Priority
                            Ensure               = "Present"
                            PsDscRunAsCredential = $SPSetupAccount
                            DependsOn            = "[SPSearchTopology]SearchTopology"
                        }
                    }#>
                }
            }

        }
     

        #**********************************************************
        # Local configuration manager settings
        #
        # This section contains settings for the LCM of the host
        # that this configuraiton is applied to
        #**********************************************************
        LocalConfigurationManager
        {
            RebootNodeIfNeeded = $true
        }
        
    }
}

#incoming email
<#
# * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * ##Function - Configure Incoming Email settings in SharePoint farm## Author - Deepak Solanki## Checks to ensure that Microsoft.SharePoint.Powershell is loaded,  
    if not, adding pssnapin## Configure Incoming Email settings in SharePoint farm# * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * * #Add SharePoint Add - ins  
Add - PSSnapin Microsoft.SharePoint.PowerShell - erroraction SilentlyContinue#  
if snapin is not installed then use this method  
    [Void][System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SharePoint")  
  
  
Write - Host "Script started to Configure Incoming Email."  
 
 
#  
Variables to get config values  
    [boolean] $Enabled = $true;  
[boolean] $UseAutomaticSettings = $false;  
[boolean] $UseDirectoryManagementService = $true;  
[boolean] $RemoteDirectoryManagementService = $false;  
$ServerAddress = "EXCHANGE.DOMAIN.COM";  
[boolean] $DLsRequireAuthenticatedSenders = $true;  
[boolean] $DistributionGroupsEnabled = $true;  
$ServerDisplayAddress = "sharepoint.company.com";  
$DropFolder = "c:\inetpub\mailroot\drop";  
 
#  
Test the drop folder location exists before proceeding with any changes  
$dropLocationTest = Get - Item $DropFolder - ErrorAction SilentlyContinue  
if ($dropLocationTest - eq $null) {  
    Throw "The drop folder location $DropFolder does not exist - please create the path and try the script again."  
}  
 
#  
Configuring Incoming E - mail Settings  
try {  
    $type = "Microsoft SharePoint Foundation Incoming E-Mail"  
    $svcinstance = Get - SPServiceInstance | where {  
        $_.TypeName - eq $type  
    }  
    $inmail = $svcinstance.Service  
  
  
    if ($inmail - ne $null) {  
        Write - Log "Configuring Incoming E-mail Settings."#  
        Enable sites on this server to receive e - mail  
        $inmail.Enabled = $Enabled  
 
        # Automatic Settings mode  
        $inmail.UseAutomaticSettings = $UseAutomaticSettings  
 
        # Use the SharePoint Directory Management Service to create distribution groups  
        $inmail.UseDirectoryManagementService = $UseDirectoryManagementService  
 
        # Use remote: Directory Management Service  
        $inmail.RemoteDirectoryManagementService = $RemoteDirectoryManagementService  
 
        # SMTP mail server  
        for incoming mail  
        $inmail.ServerAddress = $ServerAddress  
 
        # Accept messages from authenticated users only  
        $inmail.DLsRequireAuthenticatedSenders = $DLsRequireAuthenticatedSenders  
 
        # Allow creation of distribution groups from SharePoint sites  
        $inmail.DistributionGroupsEnabled = $DistributionGroupsEnabled  
 
        # E - mail server display address  
        $inmail.ServerDisplayAddress = $ServerDisplayAddress  
 
        # E - mail drop folder  
        $inmail.DropFolder = $DropFolder;  
  
        $inmail.Update();  
        Write - Host "Incoming E-mail Settings completed."  
    }  
}#  
Report  
if there is a problem setting Incoming Email  
catch {  
    Write - Host "There was a problem setting Incoming Email: $_"  
}  
#>