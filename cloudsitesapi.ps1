

function Get-WebItemValue
{
	Param(
	  [Parameter(Mandatory=$True,Position=1)]
	   [string]$Name,
	   
	   [Parameter(Mandatory=$True,Position=3)]
	   [Microsoft.PowerShell.Commands.HtmlWebResponseObject]$Request
	)
	return $request.AllElements | where { $_.tagName -eq "TR" -and $_.class -ne "topHeader"} |  where { $_.outerText -and $_.outerText.Contains($name) } | % { $_.innerText.Substring($name.length).Trim().Split()[0] }
}



function Connect-CloudSites
{
	Param(
	  [Parameter(Mandatory=$True,Position=1)]
	   [string]$Username,
	   [Parameter(Mandatory=$True,Position=2)]
	   [string]$Password,
	   [string]$BaseUrl = "https://manage.rackspacecloud.com"
	)
	$loginpath = "/Login.do"
	$loginpostvars = @{username = $Username;password = $Password}
	if (!$global:cloudsites)
	{
		$global:cloudsites = @{}
	}
	$global:cloudsites["lastusername"] = $Username
	$r = Invoke-WebRequest -UseBasicParsing -Uri ($BaseUrl+$loginpath) -Method Post -Body $loginpostvars -SessionVariable "sess"
	if ($r.BaseResponse.ResponseUri.AbsolutePath.StartsWith($loginpath))
	{
		throw "Invalid username and/or password"
	}
	if (!$global:cloudsites["sessions"])
	{
		$global:cloudsites["sessions"] = @{ $Username = @{} }
	}
	elseif (!$global:cloudsites["sessions"][$Username])
	{
		$global:cloudsites["sessions"][$Username] = @{}
	}
	$global:cloudsites["sessions"][$Username]["session"] = $sess
	$global:cloudsites["sessions"][$Username]["baseurl"] = $BaseUrl
    $global:cloudsites["sessions"][$Username]["username"] = $Username
	$global:cloudsites["lastrequest"] = $r
}

function Get-CloudSitesSession
{
	Param(
	[string]$Username = $global:cloudsites["lastusername"]
	)
	return $global:cloudsites["sessions"][$Username]
}

function Get-CloudSite
{
    Param(
    [Parameter(Position=3)]
	[string]$Username,
	[Parameter(Position=1)]
	[string]$Name,
    [Parameter(Position=2)]
	[switch]$Detail
	)
    BEGIN
    {
        if (!$global:cloudsites)
        {
            throw "You need to connect to CloudSites with Connect-CloudSites first"
        }
        if (!$Username)
        {
            $Username = $global:cloudsites["lastusername"]
        }
    }
	PROCESS
    {
        if ($Name)
        {
            GetCloudSitesDomain -Name $Name -Username $Username -Detail:$Detail.ToBool()
        }
        elseif ($Detail)
        {
            GetCloudSitesDomains -Username $Username | % { GetCloudSitesDomain -Username $Username -Name $_.Name -Detail }
        }
        else
        {
            GetCloudSitesDomains -Username $Username
        }
    }
}

function GetCloudSitesDomains
{
	Param(
	[string]$Username = $global:cloudsites["lastusername"]
	)
    $cssess = Get-CloudSitesSession -Username $Username
	$r2 = Invoke-WebRequest -Uri ($cssess["baseurl"]+"/WebsiteList.do") -WebSession $cssess["session"]
    if (!$r2.BaseResponse.ResponseUri.AbsolutePath.StartsWith("/WebsiteList.do"))
	{
		throw "Session Expired, please reconnect"
	}

	$jstable = ($r2.Scripts | where {$_.innerHTML -and $_.innerHTML.Contains("gmwElement-0")}).innerHTML

	$js = $jstable.Substring($jstable.IndexOf("tableData0:")+12).Replace("\`"","`"")
	$js = $js.Substring(0,$js.IndexOf("`"]]]}`",")+5)

	$json = ConvertFrom-Json $js
	if (!($json.location.rowsAvailable -eq $json.location.rowsReturned))
	{
		throw "Too many domains, API doesn't support this yet!"
	}
	$table = @()
	for ($i=0;$i -lt $json.rows.length;$i++)
	{
		$domain = New-Object System.Object
		$domain | Add-Member -type NoteProperty -name Name -value $json.rows[$i][2][0]
		$domain | Add-Member -type NoteProperty -name ID -value $json.rows[$i][0][0]
		$domain | Add-Member -type NoteProperty -name Type -value $json.rows[$i][1]
		$domain | Add-Member -type NoteProperty -name Settings -value $json.rows[$i][2][1]
		$table += $domain
	}
    $global:cloudsites["domainscache"] = @{ $Username = $table }
    $global:cloudsites["lastrequest"] = $r2
	$table
}

function GetCloudSitesDomain
{
	Param(
	[string]$Username = $global:cloudsites["lastusername"],
	[Parameter(Mandatory=$True,Position=1)]
	[string]$Name,
	[switch]$Detail
	)
	if (!($global:cloudsites["domainscache"] -and $global:cloudsites["domainscache"][$Username]))
	{
		GetCloudSitesDomains -Username $Username | Out-Null
        $domains = $global:cloudsites["domainscache"][$Username]
	}

	$domain = $domains | where {$_.Name -eq $Name}
	$output = New-Object System.Object
	$output | Add-Member -type NoteProperty -name Name -Value $domain.Name
	$output | Add-Member -type NoteProperty -name ID -Value $domain.ID
	$output | Add-Member -type NoteProperty -name Type -Value $domain.Type

	if ($domain.Type -eq "Full" -and $Detail)
	{
        if (!$domain.Username)
        {
            $cssess = Get-CloudSitesSession -Username $Username
		    $r3 = Invoke-WebRequest -Uri ($cssess["baseurl"]+($domain.Settings)) -WebSession $cssess["session"]
            if (!$r3.BaseResponse.ResponseUri.AbsolutePath.StartsWith(($domain.Settings -as [System.Uri]).AbsolutePath))
	        {
		        throw "Session Expired, please reconnect"
	        }
            $output | Add-Member -type NoteProperty -name Username -Value (Get-WebItemValue -Name "Username" -Request $r3)
		    $output | Add-Member -type NoteProperty -name FTPServer -Value (Get-WebItemValue -Name "FTP Server 2" -Request $r3)
		    $output | Add-Member -type NoteProperty -name FTPPath -Value (Get-WebItemValue -Name "FTP Path" -Request $r3)
		    $output | Add-Member -type NoteProperty -name Databases -Value (Get-WebItemValue -Name "Databases" -Request $r3)
		    $output | Add-Member -type NoteProperty -name FeatureSettings -Value ([System.Web.HttpUtility]::HtmlDecode( ($r3.Links | where {$_.innerText.Contains("View List") } | % { $_.href }) ))
		}
        else 
        {
            $output = $domain
        }
        
        $global:cloudsites["domaincache"] = @{ $Username = @{ $Name = $output } }
	}
	else
	{
		$output | Add-Member -type NoteProperty -name Username -Value $null
		$output | Add-Member -type NoteProperty -name FTPServer -Value $null
		$output | Add-Member -type NoteProperty -name FTPPath -Value $null
		$output | Add-Member -type NoteProperty -name Databases -Value $null
		$output | Add-Member -type NoteProperty -name FeatureSettings -Value $null
	}
    $global:cloudsites["lastrequest"] = $r3
	$output
}

function Get-CloudSiteDatabase
{
    Param(
    [Parameter(Position=4)]
	[string]$Username,
    [Parameter(Position=1,Mandatory=$True)]
	[string]$Domain,
    [Parameter(Position=2)]
	[string]$Name,
    [Parameter(Position=3)]
	[switch]$Detail
	)
    BEGIN
    {
        if (!$global:cloudsites)
        {
            throw "You need to connect to CloudSites with Connect-CloudSites first"
        }
        if (!$Username)
        {
            $Username = $global:cloudsites["lastusername"]
        }
    }
	PROCESS
    {
        if ($Name)
        {
            GetCloudSitesDomainDatabase -Name $Name -Domain $Domain -Username $Username
        }
        elseif ($Detail)
        {
            GetCloudSitesDomainDatabases -Name $Domain -Username $Username | % { GetCloudSitesDomainDatabase -Username $Username -Name $_.Name -Domain $Domain }
        }
        else
        {
            GetCloudSitesDomainDatabases -Name $Domain -Username $Username
        }
    }
}


function GetCloudSitesDomainDatabases
{
	Param(
	[string]$Username = $global:cloudsites["lastusername"],
	[Parameter(Mandatory=$True,Position=1)]
	[string]$Name
	)

	if (!($global:cloudsites["domaincache"] -and $global:cloudsites["domaincache"][$Username] -and $global:cloudsites["domaincache"][$Username][$Name]))
	{
		GetCloudSitesDomain -Username $Username -Name $Name -Detail | Out-Null
		$domain = $global:cloudsites["domaincache"][$Username][$Name]
	}
    $cssess = Get-CloudSitesSession -Username $Username
	$r4 = Invoke-WebRequest -Uri ($cssess["baseurl"]+($domain.FeatureSettings)) -WebSession $cssess["session"]
    if (!$r4.BaseResponse.ResponseUri.AbsolutePath.StartsWith(($domain.FeatureSettings -as [System.Uri]).AbsolutePath))
	{
		throw "Session Expired, please reconnect"
	}

	$jstable = ($r4.Scripts | where {$_.innerHTML  -and $_.innerHTML.Contains("gmwElement-0")}).innerHTML

	$js = $jstable.Substring($jstable.IndexOf("tableData0:")+12).Replace("\`"","`"").Replace("\`"","`"")
	$js = $js.Substring(0,$js.IndexOf("tableDefinition1:"))
	$js = $js.Substring(0,$js.LastIndexOf("}")+1)

	$json = ConvertFrom-Json $js
	
	$table = @()
	for ($i=0;$i -lt $json.rows.length;$i++)
	{
		$domain = New-Object System.Object
		$domain | Add-Member -type NoteProperty -name Name -value $json.rows[$i][2][0]
		$domain | Add-Member -type NoteProperty -name Domain -value $Name
		$domain | Add-Member -type NoteProperty -name DBSettings -value $json.rows[0][2][1]
		$table += $domain
	}
	Set-Variable -Scope Global -Value $table -Name "cloudsitesdatabasescache-$Username-$Name"
    $global:cloudsites["lastrequest"] = $r4
	$table
    
}


function GetCloudSitesDomainDatabase
{
	Param(
	[string]$Username = $global:cloudsites["lastusername"],
	[Parameter(Mandatory=$True,Position=1)]
	[string]$Name,
	[Parameter(Mandatory=$True,Position=2)]
	[string]$Domain
	)
	
	$databases = GetCloudSitesDomainDatabases -Username $Username -Name $Domain
	$database = $databases | where {$_.Name -eq $Name}
	
    $cssess = Get-CloudSitesSession -Username $Username
	$r5 = Invoke-WebRequest -Uri ($cssess["baseurl"]+($database.DBSettings)) -WebSession $cssess["session"]
    if (!$r5.BaseResponse.ResponseUri.AbsolutePath.StartsWith(($database.DBSettings -as [System.Uri]).AbsolutePath))
	{
		throw "Session Expired, please reconnect"
	}
	$jstable = ($r5.Scripts | where {$_.innerHTML  -and $_.innerHTML.Contains("gmwElement-0")}).innerHTML

	$js = $jstable.Substring($jstable.IndexOf("tableData0:")+12).Replace("\`"","`"")
	$js = $js.Substring(0,$js.IndexOf("`"]]]}`",")+5)
	$json = ConvertFrom-Json $js

	$db = New-Object System.Object
	$db | Add-Member -type NoteProperty -name Name -value (Get-WebItemValue -Request $r5 -Name "Database name")
	$db | Add-Member -type NoteProperty -name Hostname -value (Get-WebItemValue -Request $r5 -Name "Hostname")
	$db | Add-Member -type NoteProperty -name ExternalIP -value (Get-WebItemValue -Request $r5 -Name "Database Management IP Address")
	$db | Add-Member -type NoteProperty -name Users -value @()
	
	for ($i=0;$i -lt $json.rows.length;$i++)
	{	
		$user = New-Object System.Object
		$user | Add-Member -type NoteProperty -name Name -value $json.rows[$i][0][0]
		$db.Users += $user
	}
    $global:cloudsites["lastrequest"] = $r5
	$db
	
}
