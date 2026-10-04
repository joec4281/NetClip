<#
.SYNOPSIS
    Stores, lists, and retrieves public text clips using clipb.in.

.DESCRIPTION
    NetClip.ps1 uploads text to clipb.in, maintains a local list of uploaded
    clips, and retrieves clip contents by URL or list number.

    The local index is stored at:

        %LOCALAPPDATA%\NetClip\clips.json

    The local index contains clip names, URLs, and expiration timestamps.
    It does not contain clip contents.

    Uploaded clips are public and are requested to expire after one day.

.PARAMETER FileIn
    Reads a text file and uploads its contents to clipb.in.

.PARAMETER String
    Uploads the supplied string to clipb.in.

.PARAMETER List
    Lists unexpired clips saved in the local NetClip index.

.PARAMETER Retrieve
    Retrieves a clip by its number in the -List output or by URL and writes
    its contents to the console.

.EXAMPLE
    .\NetClip.ps1 -FileIn 'r:\stuff.txt'

.EXAMPLE
    .\NetClip.ps1 -String 'The quick brown fox jumped over the lazy dog.'

.EXAMPLE
    .\NetClip.ps1 -List

.EXAMPLE
    .\NetClip.ps1 -Retrieve 1

.EXAMPLE
    .\NetClip.ps1 -Retrieve 1 | Set-Clipboard

.EXAMPLE
    .\NetClip.ps1 -Retrieve 'https://clipb.in/J5ln7uP' | Set-Clipboard

.LINK
    https://clipb.in/api

.LINK
    https://jpsoft.com/forums/threads/internet-clipboard.13419/#post-77807

.NOTES
    PowerShell 5.1
    Windows 10
    Uploaded clips are public.
#>

[CmdletBinding(DefaultParameterSetName = 'List')]
param(
    [Parameter(
        ParameterSetName = 'FileIn',
        Mandatory = $true,
        Position = 0
    )]
    [ValidateNotNullOrEmpty()]
    [string] $FileIn,

    [Parameter(
        ParameterSetName = 'String',
        Mandatory = $true,
        Position = 0,
        ValueFromRemainingArguments = $true
    )]
    [ValidateNotNullOrEmpty()]
    [string[]] $String,

    [Parameter(
        ParameterSetName = 'List',
        Mandatory = $true
    )]
    [switch] $List,

    [Parameter(
        ParameterSetName = 'Retrieve',
        Mandatory = $true,
        Position = 0
    )]
    [ValidateNotNullOrEmpty()]
    [string] $Retrieve
)

begin {
    $ErrorActionPreference = 'Stop'

    $DataDirectory = Join-Path $env:LOCALAPPDATA 'NetClip'
    $DataFile = Join-Path $DataDirectory 'clips.json'
    $ClipLifetimeHours = 24

    function Ensure-DataDirectory {
        if (-not (Test-Path -LiteralPath $DataDirectory)) {
            New-Item `
                -ItemType Directory `
                -Path $DataDirectory `
                -Force |
                Out-Null
        }
    }

    function Read-ClipIndex {
        Ensure-DataDirectory

        if (-not (Test-Path -LiteralPath $DataFile)) {
            return @()
        }

        try {
            $raw = Get-Content `
                -LiteralPath $DataFile `
                -Raw `
                -Encoding UTF8
        }
        catch {
            Write-Host 'Unable to read the NetClip index file.'
            return @()
        }

        if ([string]::IsNullOrWhiteSpace($raw)) {
            return @()
        }

        try {
            $items = ConvertFrom-Json $raw
        }
        catch {
            Write-Host 'The NetClip index file is not valid JSON.'
            return @()
        }

        if ($null -eq $items) {
            return @()
        }

        return @($items)
    }

    function Write-ClipIndex {
        param(
            [Parameter(Mandatory = $true)]
            [object[]] $Items
        )

        Ensure-DataDirectory

        $json = ConvertTo-Json `
            -InputObject @($Items) `
            -Depth 5

        Set-Content `
            -LiteralPath $DataFile `
            -Value $json `
            -Encoding UTF8
    }

    function Convert-ToUtcDateTime {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Value
        )

        try {
            return [DateTime]::Parse(
                $Value,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AssumeUniversal
            ).ToUniversalTime()
        }
        catch {
            return $null
        }
    }

    function Get-ActiveClips {
        $now = [DateTime]::UtcNow
        $original = @(Read-ClipIndex)
        $active = @()

        foreach ($item in $original) {
            $expiresUtc = Convert-ToUtcDateTime `
                -Value ([string] $item.ExpiresUtc)

            if ($null -ne $expiresUtc -and $expiresUtc -gt $now) {
                $active += $item
            }
        }

        if ($active.Count -ne $original.Count) {
            Write-ClipIndex -Items $active
        }

        return @($active)
    }

    function Format-TimeRemaining {
        param(
            [Parameter(Mandatory = $true)]
            [DateTime] $ExpiresUtc
        )

        $remaining = $ExpiresUtc - [DateTime]::UtcNow

        if ($remaining.TotalSeconds -le 0) {
            return '00:00:00'
        }

        $hours = [Math]::Floor($remaining.TotalHours)

        return '{0:00}:{1:00}:{2:00}' -f `
            $hours,
            $remaining.Minutes,
            $remaining.Seconds
    }

    function Add-ClipToIndex {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Name,

            [Parameter(Mandatory = $true)]
            [string] $Url
        )

        $items = @(Get-ActiveClips)

        $createdUtc = [DateTime]::UtcNow
        $expiresUtc = $createdUtc.AddHours($ClipLifetimeHours)

        $items += [pscustomobject]@{
            Name       = $Name
            Url        = $Url
            CreatedUtc = $createdUtc.ToString(
                'yyyy-MM-ddTHH:mm:ss.fffffffZ'
            )
            ExpiresUtc = $expiresUtc.ToString(
                'yyyy-MM-ddTHH:mm:ss.fffffffZ'
            )
        }

        Write-ClipIndex -Items $items
    }

    function Publish-Clip {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Name,

            [Parameter(Mandatory = $true)]
            [string] $Text
        )

        $request = @{
            name     = $Name
            text     = $Text
            unlisted = 'false'
            remove   = 'day'
        }

        $body = ConvertTo-Json $request

        try {
            $response = Invoke-RestMethod `
                -Uri 'https://clipb.in/api/post_data' `
                -Method Post `
                -ContentType 'application/json; charset=utf-8' `
                -Body $body
        }
        catch {
            Write-Host "Unable to upload the clip: $($_.Exception.Message)"
            return
        }

        if ($null -eq $response -or $null -eq $response.id) {
            Write-Host 'clipb.in returned no clip identifier.'
            return
        }

        $url = 'https://clipb.in/{0}' -f $response.id

        Add-ClipToIndex `
            -Name $Name `
            -Url $url

        Write-Output $url
    }

    function Resolve-ClipReference {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Reference
        )

        if ($Reference -match '^\d+$') {
            $number = [int] $Reference
            $items = @(Get-ActiveClips)

            if ($number -lt 1 -or $number -gt $items.Count) {
                Write-Host "Clip number '$Reference' was not found. Run -List to see available clips."
                return $null
            }

            $resolvedUrl = [string] $items[$number - 1].Url

            if ([string]::IsNullOrWhiteSpace($resolvedUrl)) {
                Write-Host "Clip number '$Reference' has no URL."
                return $null
            }

            return $resolvedUrl
        }

        if ($Reference -match '^https://clipb\.in/[A-Za-z0-9_-]+/?$') {
            return $Reference.TrimEnd('/')
        }

        Write-Host "Invalid clip reference '$Reference'. Use a list number or a clipb.in URL."
        return $null
    }

    function Get-ClipText {
        param(
            [Parameter(Mandatory = $true)]
            [string] $Reference
        )

        $url = Resolve-ClipReference -Reference $Reference

        if ($null -eq $url -or [string]::IsNullOrWhiteSpace($url)) {
            return $null
        }

        $rawUrl = '{0}/raw' -f $url.TrimEnd('/')

        try {
            $response = Invoke-WebRequest `
                -Uri $rawUrl `
                -UseBasicParsing
        }
        catch {
            Write-Host "Unable to retrieve '$url': $($_.Exception.Message)"
            return $null
        }

        if ($null -eq $response.Content) {
            Write-Host "The clip at '$url' returned no content."
            return $null
        }

        return [string] $response.Content
    }

    function Show-ClipList {
        $items = @(Get-ActiveClips)

        if ($items.Count -eq 0) {
            Write-Host 'No unexpired clips are saved.'
            return
        }

        $index = 1

        foreach ($item in $items) {
            $expiresUtc = Convert-ToUtcDateTime `
                -Value ([string] $item.ExpiresUtc)

            if ($null -eq $expiresUtc) {
                continue
            }

            $remaining = Format-TimeRemaining `
                -ExpiresUtc $expiresUtc

            $name = [string] $item.Name

            if ($name.Length -gt 31) {
                $name = $name.Substring(0, 31)
            }

            '{0} {1,-31} {2} remaining {3}' -f `
                $index,
                $name,
                $remaining,
                $item.Url

            $index++
        }
    }
}

process {
    switch ($PSCmdlet.ParameterSetName) {
        'FileIn' {
            if (-not (Test-Path -LiteralPath $FileIn -PathType Leaf)) {
                Write-Host "The file '$FileIn' does not exist."
                return
            }

            try {
                $text = [System.IO.File]::ReadAllText($FileIn)
            }
            catch {
                Write-Host "Unable to read '$FileIn': $($_.Exception.Message)"
                return
            }

            Publish-Clip `
                -Name $FileIn `
                -Text $text
        }

        'String' {
            $text = $String -join ' '
            $trimmed = $text.Trim()

            if ($trimmed.Length -eq 0) {
                Write-Host 'The -String argument cannot be empty.'
                return
            }

            $nameLength = [Math]::Min(31, $trimmed.Length)
            $name = $trimmed.Substring(0, $nameLength)

            Publish-Clip `
                -Name $name `
                -Text $text
        }

        'List' {
            Show-ClipList
        }

        'Retrieve' {
            $text = Get-ClipText -Reference $Retrieve

            if ($null -eq $text) {
                return
            }

            Write-Output $text
        }
    }
}
