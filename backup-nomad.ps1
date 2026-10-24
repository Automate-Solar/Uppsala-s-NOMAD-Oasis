
$ErrorActionPreference = "Stop"

# Change this to your external backup drive.
$BackupRoot = "C:\Users\parch602\Desktop\NOMAD-backups"

$Timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$DumpName = "nomad_oasis_v1_$Timestamp.archive"
$LogFile = Join-Path $BackupRoot "backup.log"

New-Item -ItemType Directory -Force -Path $BackupRoot | Out-Null

try {
    Add-Content $LogFile "[$(Get-Date)] Starting NOMAD backup"

    # Check that MongoDB is running.
    $running = docker inspect -f '{{.State.Running}}' nomad_oasis_mongo
    if ($LASTEXITCODE -ne 0 -or $running -ne "true") {
        throw "MongoDB container is not running."
    }

    # Create the database dump in the mounted backup directory.
    docker exec nomad_oasis_mongo mongodump `
        --db nomad_oasis_v1 `
        --archive="/backup/$DumpName"

    if ($LASTEXITCODE -ne 0) {
        throw "mongodump failed."
    }

    # Create a separate folder for this backup.
    $Destination = Join-Path $BackupRoot $Timestamp
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null

    # Copy the database dump.
    Copy-Item `
        (Join-Path $PSScriptRoot ".volumes\mongo\$DumpName") `
        $Destination

    # Copy NOMAD's uploaded files.
    $SourceFS = Join-Path $PSScriptRoot ".volumes\fs"
    $DestinationFS = Join-Path $Destination "fs"

    if (-not (Test-Path $SourceFS)) {
        throw "NOMAD filesystem directory not found: $SourceFS"
    }

    robocopy $SourceFS $DestinationFS /E /COPY:DAT /R:2 /W:5
    $CopyCode = $LASTEXITCODE

    if ($CopyCode -ge 8) {
        throw "Raw-file backup failed. Robocopy exit code: $CopyCode"
    }

    Add-Content $LogFile "[$(Get-Date)] Backup completed: $Destination"
}
catch {
    Add-Content $LogFile "[$(Get-Date)] ERROR: $($_.Exception.Message)"
    throw
}
