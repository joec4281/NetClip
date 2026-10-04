# NetClip
PowerShell 5.1 script for working with https://clipb.in/ from Take Command Console v36

This PowerShell 5.1 script will NOT completely work when run from PowerShell 5.1 without modification.

Specifically, it will fail when using the `Clip2Win` argument in PowerShell 5.1

Take Command Console (TCC) uses the PShell command to execute PowerShell 5.1 commands, functions, and scripts (`.ps1` files).

TCC does this by creating its own in-process PowerShell session.

Ref: https://jpsoft.com/help/pshell.htm?q=pshell
  
In order to work with the Windows clipboard from PowerShell code invoked via PShell,
it is necessary to run the PowerShell code in an STA session, which TCC PShell does not do.

```  
Unable to access the Windows clipboard.
Run Windows PowerShell in an STA session.  
```

The work-around is to callback into TCC from the `NetClip.ps1` file using `[TakeCommand.PowerShellHost]`

```
function Copy-ToWindowsClipboard {
		param(
				[Parameter(Mandatory = $true)]
				[string] $Text
		)

		try {
				$tccCommand = 'clip /s clip0: $Text'
				[void][TakeCommand.PowerShellHost]::InvokeCommand($tccCommand)
		}
		catch {
				Write-Host 'Unable to access the Windows clipboard.'
				Write-Host $_.Exception.Message
		}
}
```
If you just want to run from PowerShell 5.1, use this function instead;

```  
function Copy-ToWindowsClipboard {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text
    )

    Add-Type -AssemblyName System.Windows.Forms

    try {
        [System.Windows.Forms.Clipboard]::SetText($Text)
    }
    catch {
        Write-Host 'Unable to access the Windows clipboard.'
        Write-Host 'Run Windows PowerShell in an STA session.'
    }
}
```
