# NetClip
PowerShell 5.1 script for working with https://clipb.in/ from Take Command Console v36

`NetClip.btm` is a wrapper for `NetClip.ps1`,  
making it easier to use `NetClip.ps1` from TCC v36.

USAGE EXAMPLES for TCC v36;

NetClip -FileIn 'r:\stuff.txt'

NetClip -String 'The quick brown fox jumped over the lazy dog.'

NetClip -List

NetClip -Retrieve 1

NetClip -Retrieve 1 > clip:
  