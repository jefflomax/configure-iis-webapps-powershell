# IIS Configuration
#
# Prerequisites:
# Set-ExecutionPolicy RemoteSigned
# Import-Module WebAdministation (or ability to execute)
# If using server try Import-Module ServerManager
#
# PowerShell gotchas:
# String interpolation only works in double quotes "var: $good", not single quotes '$bad'
# WebAdministration will not accept / or \ path delimiters, you MUST pass the correct one
# Cannot use PowerShell to set ASP.NET Impersonation on a workstation, thanks SO MUCH for that
# Set-ItemProperty parameters like applicationPool are case sensitive
#
$projectName = "myApp"
$appPool = ".NET v4.5 Classic" 
#Three web application folders are inside this location
$sandbox = "C:\src\myApp\WebApp"
$website = "Default Web Site"
$clean = $false

$anonAuthFilter = "/system.WebServer/security/authentication/AnonymousAuthentication"
$windowsAuthFilter = "/system.WebServer/security/authentication/windowsAuthentication"
$basicAuthFilter = "/system.webServer/security/authentication/basicAuthentication"


if ((Get-Module "WebAdministration" -ErrorAction SilentlyContinue) -eq $null){
	Import-Module WebAdministration
}
#Servers Only
#if ((Get-Module "ServerManager" -ErrorAction SilentlyContinue) -eq $null) {
#	Import-Module ServerManager
#}

function Create-Application( [string]$appName, [string]$path ) {
	if ( (Test-Path "IIS:\Sites\$website\$appName") -eq $false ) {
		$physicalPath = if( $path -eq "" ) { $sandbox } else { "$sandbox\$path" }
		Write-Host "Physical Path: $physicalPath"
		New-Item "IIS:\Sites\$website\$appName" -type Application -physicalpath $physicalPath
		Write-Host "$appName created"
		#IIS:\>New-WebApplication -Name testApp -Site 'Default Web Site' -PhysicalPath c:\test -ApplicationPool DefaultAppPool
	} else {
		Write-Host "$appName already exists"
	}
}

function Remove-Application( [string]$appName ) {
	if ( (Test-Path "IIS:\Sites\$website\$appName") -eq $true ) {
		Remove-Item "IIS:\Sites\$website\$appName" -recurse
		Write-Host "$appName removed"
		#IIS:\>Remove-WebApplication -Name TestApp -Site "Default Web Site"
	}
}

function Set-AppPool( [string]$appName ) {
	$webApp = Get-ItemProperty "IIS:\Sites\$website\$appName"
	if( $webApp.applicationPool -eq $appPool ){
		Write-Host "$appName Application Pools is already $appPool"
	} else {
		Set-ItemProperty "IIS:\Sites\$website\$appName" applicationPool $appPool
		Write-Host "Set $appName to Application Pool $appPool"
	}
}

function Set-AnonymousAuthentication( [string]$appName, [bool]$value ) {
	$anonAuth = Get-WebConfigurationProperty -filter $anonAuthFilter -name Enabled -location "$website/$appName"
	if( $anonAuth.Value -eq $value ){
		Write-Host "$appName Anonymous Authentication is already $value"
	} else {
		Set-WebConfigurationProperty -filter $anonAuthFilter -name Enabled -value $value -location "$website/$appName"
		Write-Host "Anonymous Authentication now $value on $appName"
	}
}

function Enable-WindowsAuthentication( [string]$appName ) {
	Set-WebConfigurationProperty -filter $windowsAuthFilter -name Enabled -value $true -location "$website/$appName"
}

function Enable-FormsAuthentication( [string]$appName ) {
	$config = (Get-WebConfiguration system.web/authentication "IIS:Sites\$website\$appName")
	$config.mode = "Forms"
	$config | Set-WebConfiguration system.web/authentication
}

function Enable-AspNetImpersonation( [string]$appName ){

# On a Server with ServerManager loaded, Set-WebConfigurationProperty may work
# Since this script runs on a workstation, resort to shelling out to appcmd, as
# it can handle the transacted call.  Otherwise the properties are read only
#	Set-WebConfigurationProperty -filter system.web/identity -name impersonate -value $true -location "$website/$appName" 	

	$aspNetImpersonation = Get-WebConfigurationProperty -filter system.web/identity -name impersonate -location "$website/$appName"
	if( $aspNetImpersonation.Value -eq $true ){
		Write-Host "ASP.NET Impersonation is already enabled"
	} else {
		$appCmdFilePath = "$Env:SystemRoot\System32\inetsrv\appcmd.exe"
& $appCmdFilePath set config "$website/$appname" -section:system.web/identity /impersonate:"True" 
	}
}

Write-Host "Setting up $projectName IIS Settings"

if( $clean -eq $true ){
	Write-Host "Clean Enabled, removing Web Applications"
	Remove-Application "WebApp/WebSecurity"
	Remove-Application "WebApp"
	Remove-Application "WebServices"
}


$is64BitOS = [Environment]::Is64BitOperatingSystem

if( $is64BitOS ) {
	Write-Host "64 Bit OS, Check/Set Enable 32 bit Applications"

	$enable32Bit = "enable32BitAppOnWin64"
	$32BitAppsEnabled = Get-ItemProperty "IIS:\apppools\$appPool" -Name $enable32Bit
	if ( $32BitAppsEnabled.Value -eq $False ) {
		Write-Host "Enabling 32 bit Applications"
		Set-ItemProperty "IIS:\apppools\$appPool" -Name $enable32Bit -Value "True"
	}
	$32BitAppsEnabled = Get-ItemProperty "IIS:\apppools\$appPool" -Name $enable32Bit
	Write-Host "32 bit applications are Enabled: $($32BitAppsEnabled.Value)"
} else {
	Write-Host "32 bit OS"
}

# Create WebServices
Create-Application "WebServices" "Services"
Set-AppPool "WebServices"
Set-AnonymousAuthentication "WebServices" $true

# Create WebApp
Create-Application "WebApp" "Web"
Set-AppPool "WebApp"
Enable-FormsAuthentication "WebApp"

# Create WebSecurity
# This Web Application is inside another one, be careful with the
# kind of slashes
Create-Application "WebApp\WebSecurity" "Web\WebAuthentication"
Set-AppPool "WebApp\WebSecurity"
Set-AnonymousAuthentication "WebApp/WebSecurity" $false
Enable-WindowsAuthentication "WebApp/WebSecurity"
Enable-AspNetImpersonation "WebApp/WebSecurity"

Write-Host "IIS Setup Complete"

