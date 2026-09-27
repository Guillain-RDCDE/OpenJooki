<# : OpenJooki - move a Jooki to a bigger SD card (Windows). Double-click this file.
@echo off
setlocal
set "JOOKI_SD_SELF=%~f0"
if defined JOOKI_SD_TEST goto run
if defined JOOKI_SD_PREVIEW goto run
net session >nul 2>&1
if errorlevel 1 (
  powershell -NoProfile -Command "Start-Process -FilePath $env:JOOKI_SD_SELF -Verb RunAs"
  exit /b
)
:run
powershell -NoProfile -ExecutionPolicy Bypass -STA -Command "iex ([IO.File]::ReadAllText($env:JOOKI_SD_SELF, [Text.Encoding]::UTF8))"
exit /b
#>
# ----------------------------------------------------------------------------------------------
# OpenJooki - move a Jooki's content to a bigger SD card, on Windows, with nothing to install.
#
#  1. The Jooki's card is READ ONLY (never written) and copied to Documents (also a backup).
#  2. The copy is written to the new card, read back and compared, then the last partition
#     ("content", the music) is grown to the end of the card (GPT: entry, both headers, CRCs).
#  3. Back in the Jooki, its own start-up script (S10_init_fs.sh, resize2fs) grows the
#     filesystem to the partition at the first boot.
# Only removable cards and USB disks are offered, never a system disk. The source must have
# the Jooki's layout; the target must be bigger; the target's name and size are confirmed.
# Bench: JOOKI_SD_TEST="clone|<src.img>|<dst.img>" or "grow|<dst.img>" runs on files, no window;
# "disks|<source disk>|<target disk>|<image>" runs the window's two steps on real disks (admin).
# Docs: JOOKI_SD_PREVIEW=<file.png> draws the window and closes it (JOOKI_SD_DEMO=1: an example
# card reader in the list, JOOKI_SD_LANG=en|fr); nothing is read or written then.
# ----------------------------------------------------------------------------------------------
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Text;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public static class JookiSd {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern SafeFileHandle CreateFile(string name, uint access, uint share, IntPtr sa, uint disposition, uint flags, IntPtr template);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool DeviceIoControl(SafeFileHandle h, uint code, IntPtr inBuf, uint inSize, IntPtr outBuf, uint outSize, out uint returned, IntPtr overlapped);

    const uint GENERIC_READ = 0x80000000, GENERIC_WRITE = 0x40000000, SHARE_RW = 3, OPEN_EXISTING = 3, WRITE_THROUGH = 0x80000000;
    const uint FSCTL_LOCK_VOLUME = 0x00090018, FSCTL_DISMOUNT_VOLUME = 0x00090020;
    public const int Sector = 512;

    // A physical disk (\\.\PhysicalDriveN) or, on the bench, a plain file.
    public static FileStream Open(string path, bool write) {
        if (!path.StartsWith(@"\\.\")) return new FileStream(path, write ? FileMode.Open : FileMode.Open, write ? FileAccess.ReadWrite : FileAccess.Read, FileShare.ReadWrite, 1 << 20);
        SafeFileHandle h = CreateFile(path, write ? (GENERIC_READ | GENERIC_WRITE) : GENERIC_READ, SHARE_RW, IntPtr.Zero, OPEN_EXISTING, write ? WRITE_THROUGH : 0, IntPtr.Zero);
        if (h.IsInvalid) throw new IOException("cannot open " + path + " (error " + Marshal.GetLastWin32Error() + ")");
        return new FileStream(h, write ? FileAccess.ReadWrite : FileAccess.Read, 1);
    }

    // Lock and dismount a volume of the target card; the handle is kept open while we write.
    public static SafeFileHandle LockVolume(string volumePath) {
        SafeFileHandle h = CreateFile(volumePath.TrimEnd('\\'), GENERIC_READ | GENERIC_WRITE, SHARE_RW, IntPtr.Zero, OPEN_EXISTING, 0, IntPtr.Zero);
        if (h.IsInvalid) return null;
        uint r;
        DeviceIoControl(h, FSCTL_LOCK_VOLUME, IntPtr.Zero, 0, IntPtr.Zero, 0, out r, IntPtr.Zero);
        DeviceIoControl(h, FSCTL_DISMOUNT_VOLUME, IntPtr.Zero, 0, IntPtr.Zero, 0, out r, IntPtr.Zero);
        return h;
    }

    static uint[] crcTable;
    public static uint Crc32(byte[] b, int off, int len) {
        if (crcTable == null) {
            crcTable = new uint[256];
            for (uint i = 0; i < 256; i++) { uint c = i; for (int k = 0; k < 8; k++) c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1; crcTable[i] = c; }
        }
        uint crc = 0xFFFFFFFF;
        for (int i = off; i < off + len; i++) crc = crcTable[(crc ^ b[i]) & 0xFF] ^ (crc >> 8);
        return crc ^ 0xFFFFFFFF;
    }

    public static byte[] ReadAt(Stream s, long lba, int sectors) {
        byte[] b = new byte[sectors * Sector];
        s.Seek(lba * Sector, SeekOrigin.Begin);
        int got = 0;
        while (got < b.Length) { int n = s.Read(b, got, b.Length - got); if (n <= 0) throw new IOException("short read at sector " + lba); got += n; }
        return b;
    }
    public static void WriteAt(Stream s, long lba, byte[] b) { s.Seek(lba * Sector, SeekOrigin.Begin); s.Write(b, 0, b.Length); s.Flush(); }

    // The first 34 sectors of a Jooki card: protective MBR, GPT header, 128 entries of 128 bytes,
    // the last partition named "content" (Linux data) and a "config" partition. Returns a short
    // description, or throws with the reason it is not a Jooki card.
    public static string CheckJooki(byte[] head) {
        if (Encoding.ASCII.GetString(head, 512, 8) != "EFI PART") throw new InvalidDataException("no GPT partition table");
        if (Crc32(head, 1024, 128 * 128) != BitConverter.ToUInt32(head, 512 + 88)) throw new InvalidDataException("GPT entries damaged");
        long lastEnd = -1; string lastName = null; bool config = false; int count = 0;
        for (int i = 0; i < 128; i++) {
            int e = 1024 + i * 128;
            bool empty = true; for (int k = 0; k < 16; k++) if (head[e + k] != 0) { empty = false; break; }
            if (empty) continue;
            count++;
            string name = Encoding.Unicode.GetString(head, e + 56, 72).TrimEnd('\0');
            int z = name.IndexOf('\0'); if (z >= 0) name = name.Substring(0, z);
            long end = BitConverter.ToInt64(head, e + 40);
            if (name == "config") config = true;
            if (end > lastEnd) { lastEnd = end; lastName = name; }
        }
        if (lastName != "content" || !config) throw new InvalidDataException("not the layout of a Jooki card (" + count + " partitions, last one '" + lastName + "')");
        return count + " partitions, music partition ends at sector " + lastEnd;
    }

    // Grow the last partition ("content") to the end of the disk: protective MBR, primary header,
    // entries, backup entries + backup header at the new end, all CRCs. Returns the new size of
    // the partition in sectors. Throws (and writes nothing) if anything is unexpected.
    public static long GrowContent(Stream s, long totalSectors) {
        byte[] head = ReadAt(s, 0, 34);
        CheckJooki(head);
        if (BitConverter.ToUInt32(head, 512 + 12) != 92 || BitConverter.ToInt64(head, 512 + 72) != 2
            || BitConverter.ToUInt32(head, 512 + 80) != 128 || BitConverter.ToUInt32(head, 512 + 84) != 128)
            throw new InvalidDataException("unexpected GPT geometry");
        long newLast = totalSectors - 34;                 // 32 sectors of entries + backup header at the end
        long oldLast = BitConverter.ToInt64(head, 512 + 48);
        if (newLast < oldLast) throw new InvalidDataException("the card is smaller than the Jooki's layout");
        int idx = -1; long lastEnd = -1;
        for (int i = 0; i < 128; i++) {
            int e = 1024 + i * 128; long end = BitConverter.ToInt64(head, e + 40);
            bool empty = true; for (int k = 0; k < 16; k++) if (head[e + k] != 0) { empty = false; break; }
            if (!empty && end > lastEnd) { lastEnd = end; idx = i; }
        }
        int ce = 1024 + idx * 128;
        long start = BitConverter.ToInt64(head, ce + 32);
        Array.Copy(BitConverter.GetBytes(newLast), 0, head, ce + 40, 8);
        uint entriesCrc = Crc32(head, 1024, 128 * 128);

        // protective MBR: one 0xEE partition covering the disk (capped at 32 bits)
        long mbrLen = Math.Min(totalSectors - 1, 0xFFFFFFFFL);
        Array.Copy(BitConverter.GetBytes((uint)mbrLen), 0, head, 446 + 12, 4);

        byte[] primary = new byte[512]; Array.Copy(head, 512, primary, 0, 512);
        Array.Copy(BitConverter.GetBytes(totalSectors - 1), 0, primary, 32, 8);    // alternate LBA
        Array.Copy(BitConverter.GetBytes(newLast), 0, primary, 48, 8);             // last usable LBA
        Array.Copy(BitConverter.GetBytes(entriesCrc), 0, primary, 88, 4);
        SetHeaderCrc(primary);

        byte[] backup = new byte[512]; Array.Copy(primary, backup, 512);
        Array.Copy(BitConverter.GetBytes(totalSectors - 1), 0, backup, 24, 8);     // my LBA
        Array.Copy(BitConverter.GetBytes(1L), 0, backup, 32, 8);                   // alternate LBA
        Array.Copy(BitConverter.GetBytes(totalSectors - 33), 0, backup, 72, 8);    // entries LBA
        SetHeaderCrc(backup);

        byte[] entries = new byte[128 * 128]; Array.Copy(head, 1024, entries, 0, entries.Length);
        // backup first (at the new end, outside every partition), then the primary: a cut in the
        // middle leaves a primary that still describes the old, valid layout
        WriteAt(s, totalSectors - 33, entries);
        WriteAt(s, totalSectors - 1, backup);
        Array.Copy(primary, 0, head, 512, 512);
        WriteAt(s, 0, head);
        return newLast - start + 1;
    }

    static void SetHeaderCrc(byte[] h) {
        Array.Clear(h, 16, 4);
        Array.Copy(BitConverter.GetBytes(Crc32(h, 0, 92)), 0, h, 16, 4);
    }

    // After the grow: both headers valid, entries CRC valid, the music partition ends at the last usable sector.
    public static string Verify(Stream s, long totalSectors) {
        byte[] head = ReadAt(s, 0, 34);
        CheckJooki(head);
        byte[] b = ReadAt(s, totalSectors - 33, 33);
        byte[] ph = new byte[512]; Array.Copy(head, 512, ph, 0, 512);
        byte[] bh = new byte[512]; Array.Copy(b, 32 * 512, bh, 0, 512);
        foreach (byte[] h in new byte[][] { ph, bh }) {
            uint want = BitConverter.ToUInt32(h, 16); byte[] c = (byte[])h.Clone(); Array.Clear(c, 16, 4);
            if (Encoding.ASCII.GetString(h, 0, 8) != "EFI PART" || Crc32(c, 0, 92) != want) throw new InvalidDataException("GPT header CRC");
        }
        if (Crc32(b, 0, 128 * 128) != BitConverter.ToUInt32(bh, 88)) throw new InvalidDataException("backup entries CRC");
        if (BitConverter.ToInt64(ph, 48) != totalSectors - 34) throw new InvalidDataException("last usable sector");
        return CheckJooki(head);
    }
}
'@

$fr = if ($env:JOOKI_SD_LANG) { $env:JOOKI_SD_LANG -eq 'fr' } else { (Get-UICulture).TwoLetterISOLanguageName -eq 'fr' }
function T([string]$en, [string]$fra) { if ($fr) { $fra } else { $en } }
$Chunk = 4MB

# Copy $length bytes from $from (at $fromOff) to $to (at $toOff), 4 MB at a time; returns the SHA-256.
function Copy-Region($from, $to, [long]$fromOff, [long]$toOff, [long]$length, [scriptblock]$progress) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $buf = New-Object byte[] $Chunk
    $from.Seek($fromOff, 'Begin') | Out-Null
    if ($to) { $to.Seek($toOff, 'Begin') | Out-Null }
    [long]$done = 0
    while ($done -lt $length) {
        $want = [int][Math]::Min($Chunk, $length - $done)
        $got = 0
        while ($got -lt $want) { $n = $from.Read($buf, $got, $want - $got); if ($n -le 0) { throw "short read" }; $got += $n }
        if ($to) { $to.Write($buf, 0, $want) }
        $sha.TransformBlock($buf, 0, $want, $null, 0) | Out-Null
        $done += $want
        if ($progress) { & $progress $done $length }
    }
    if ($to) { $to.Flush() }
    $sha.TransformFinalBlock((New-Object byte[] 0), 0, 0) | Out-Null
    return [BitConverter]::ToString($sha.Hash)
}

# Step 2 (and the bench): image -> target; data first, read back and compared, then the table, then the grow.
function Write-Card([string]$imagePath, $target, [long]$targetBytes, [scriptblock]$progress, [scriptblock]$status) {
    $img = [JookiSd]::Open($imagePath, $false)
    try {
        $srcBytes = $img.Length
        $head = [JookiSd]::ReadAt($img, 0, 34)
        [JookiSd]::CheckJooki($head) | Out-Null
        if ($targetBytes -le $srcBytes) { throw (T "The new card is not bigger than the Jooki's card." "La nouvelle carte n'est pas plus grande que celle du Jooki.") }
        $data = 34 * 512
        & $status (T "Erasing the old partition table of the new card..." "Effacement de l'ancienne table de la nouvelle carte...")
        [JookiSd]::WriteAt($target, 0, (New-Object byte[] (34 * 512)))
        & $status (T "Writing (step 1 of 2)..." "Écriture (étape 1 sur 2)...")
        $h1 = Copy-Region $img $target $data $data ($srcBytes - $data) $progress
        & $status (T "Checking every byte (step 2 of 2)..." "Vérification de chaque octet (étape 2 sur 2)...")
        $h2 = Copy-Region $target $null $data 0 ($srcBytes - $data) $progress
        if ($h1 -ne $h2) { throw (T "The new card did not give back what was written: it may be faulty." "La nouvelle carte ne relit pas ce qui a été écrit : elle est peut-être défectueuse.") }
        & $status (T "Growing the music partition..." "Agrandissement de la partition musique...")
        [JookiSd]::WriteAt($target, 0, $head)
        $sectors = [JookiSd]::GrowContent($target, [long]($targetBytes / 512))
        [JookiSd]::Verify($target, [long]($targetBytes / 512)) | Out-Null
        return $sectors
    } finally { $img.Dispose() }
}

# Step 1: the Jooki's card (disk number) -> image file. The card is opened read-only.
function Read-Card([int]$num, [long]$size, [string]$image, [scriptblock]$progress, [scriptblock]$status) {
    $src = [JookiSd]::Open("\\.\PhysicalDrive$num", $false)
    try {
        try { [JookiSd]::CheckJooki([JookiSd]::ReadAt($src, 0, 34)) | Out-Null }
        catch { throw (T "This is not a Jooki's card (or it cannot be read). Choose the card taken out of the Jooki." "Ce n'est pas la carte d'un Jooki (ou elle est illisible). Choisis la carte sortie du Jooki.") }
        $out = New-Object IO.FileStream($image, 'CreateNew', 'Write')
        try {
            & $status (T "Reading the Jooki's card..." "Lecture de la carte du Jooki...")
            Copy-Region $src $out 0 0 $size $progress | Out-Null
        } finally { $out.Dispose() }
    } finally { $src.Dispose() }
}

# Step 2: image -> the new card (disk number): its partitions removed, its volumes locked and
# dismounted while we write, then Windows told to read the new table.
function Write-CardToDisk([int]$num, [long]$size, [string]$image, [scriptblock]$progress, [scriptblock]$status) {
    try { Clear-Disk -Number $num -RemoveData -RemoveOEM -Confirm:$false } catch { }
    $locks = @()
    foreach ($p in (Get-Partition -DiskNumber $num -ErrorAction SilentlyContinue)) {
        foreach ($v in $p.AccessPaths) { if ($v -like '\\?\Volume*') { $h = [JookiSd]::LockVolume($v); if ($h) { $locks += $h } } }
    }
    $t = [JookiSd]::Open("\\.\PhysicalDrive$num", $true)
    try { $n = Write-Card $image $t $size $progress $status } finally { $t.Dispose(); foreach ($h in $locks) { $h.Dispose() } }
    try { Update-Disk -Number $num } catch { }
    return $n
}

# ---------------------------------------------------------------- bench mode (files, no window)
if ($env:JOOKI_SD_TEST) {
    $a = $env:JOOKI_SD_TEST.Split('|')
    $say = { param($m) Write-Host $m }
    if ($a[0] -eq 'clone') {
        $t = [JookiSd]::Open($a[2], $true)
        try { $n = Write-Card $a[1] $t $t.Length $null $say } finally { $t.Dispose() }
    } elseif ($a[0] -eq 'disks') {       # "disks|<source disk>|<target disk>|<image file>": the window's own two steps
        $sd = Get-Disk -Number ([int]$a[1]); $td = Get-Disk -Number ([int]$a[2])
        Read-Card $sd.Number $sd.Size $a[3] $null $say
        if ($td.Size -le $sd.Size) { throw "target not bigger" }
        $n = Write-CardToDisk $td.Number $td.Size $a[3] $null $say
    } elseif ($a[0] -eq 'grow') {
        $t = [JookiSd]::Open($a[1], $true)
        try { $n = [JookiSd]::GrowContent($t, [long]($t.Length / 512)); [JookiSd]::Verify($t, [long]($t.Length / 512)) | Out-Null } finally { $t.Dispose() }
    }
    Write-Host ("OK content partition = {0} sectors ({1:N1} GB)" -f $n, ($n * 512 / 1e9))
    return
}

# ---------------------------------------------------------------- the window
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Only card readers: an SD/MMC bus, or a USB device Windows reports as REMOVABLE media (a card
# reader or a stick), never an external hard disk ("External hard disk media"), never a system disk.
function Get-Cards {
    $removable = @(Get-CimInstance Win32_DiskDrive | Where-Object { $_.MediaType -like 'Removable*' } | ForEach-Object { [int]$_.Index })
    Get-Disk | Where-Object {
        -not $_.IsSystem -and -not $_.IsBoot -and $_.LogicalSectorSize -eq 512 -and
        $_.Size -gt 1GB -and $_.Size -le 512GB -and
        ($_.BusType -in 'SD', 'MMC' -or ($_.BusType -eq 'USB' -and $removable -contains [int]$_.Number))
    } | Sort-Object Number
}
# numbers written like the interface's language (7,9 Go / 7.9 GB), whatever Windows' own settings
$Nums = if ($fr) { [Globalization.CultureInfo]::GetCultureInfo('fr-FR') } else { [Globalization.CultureInfo]::InvariantCulture }
function Fmt([string]$f) { [string]::Format($Nums, $f, $args) }
function Label-Of($d) { Fmt "{0}  ·  {1:N1} {2}" $d.FriendlyName ($d.Size / 1e9) (T "GB" "Go") }

$form = New-Object Windows.Forms.Form
$form.Text = T "Jooki: move to a bigger SD card" "Jooki : passer à une plus grande carte SD"
$form.ClientSize = New-Object Drawing.Size(560, 330); $form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'; $form.MaximizeBox = $false
$form.Font = New-Object Drawing.Font('Segoe UI', 10)

$title = New-Object Windows.Forms.Label; $title.Location = '20,15'; $title.Size = '520,30'
$title.Font = New-Object Drawing.Font('Segoe UI', 13, [Drawing.FontStyle]::Bold)
$text = New-Object Windows.Forms.Label; $text.Location = '20,50'; $text.Size = '520,90'
$combo = New-Object Windows.Forms.ComboBox; $combo.Location = '20,145'; $combo.Size = '400,28'; $combo.DropDownStyle = 'DropDownList'
$refresh = New-Object Windows.Forms.Button; $refresh.Location = '430,144'; $refresh.Size = '110,30'; $refresh.Text = T "Refresh" "Actualiser"
$go = New-Object Windows.Forms.Button; $go.Location = '20,190'; $go.Size = '520,44'
$go.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
$bar = New-Object Windows.Forms.ProgressBar; $bar.Location = '20,250'; $bar.Size = '520,22'; $bar.Maximum = 1000
$info = New-Object Windows.Forms.Label; $info.Location = '20,280'; $info.Size = '520,40'
$form.Controls.AddRange(@($title, $text, $combo, $refresh, $go, $bar, $info))

$state = @{ step = 1; image = $null; srcBytes = 0 }
$progress = { param($done, $total) $bar.Value = [int](1000 * $done / $total); $info.Text = Fmt "{0:N1} / {1:N1} {2}" ($done / 1e9) ($total / 1e9) (T "GB" "Go"); [Windows.Forms.Application]::DoEvents() }
$status = { param($m) $title.Text = $m; [Windows.Forms.Application]::DoEvents() }

function Fill-Cards {
    $combo.Items.Clear()
    $cards = if ($env:JOOKI_SD_DEMO -and $env:JOOKI_SD_PREVIEW) { @([pscustomobject]@{ FriendlyName = 'Generic SD/MMC Card Reader'; Size = 7948206080; Number = -1 }) } else { Get-Cards }   # picture for the docs
    foreach ($d in $cards) { $combo.Items.Add([pscustomobject]@{ Disk = $d; Text = (Label-Of $d) }) | Out-Null }
    $combo.DisplayMember = 'Text'
    if ($combo.Items.Count) { $combo.SelectedIndex = 0 }
    $go.Enabled = $combo.Items.Count -gt 0
    if (-not $combo.Items.Count) { $info.Text = T "No card found: put the card in, then click Refresh." "Aucune carte détectée : mets la carte, puis clique sur Actualiser." }
}
function Show-Step {
    $bar.Value = 0; $info.Text = ''
    if ($state.step -eq 1) {
        $title.Text = T "1. The Jooki's card" "1. La carte du Jooki"
        $text.Text = T "Take the SD card out of the Jooki and put it in this computer (with a card reader if needed), then choose it below.`nIt is only READ: nothing is ever written on it. A copy is kept in your Documents." "Sors la carte SD du Jooki et mets-la dans cet ordinateur (avec un lecteur de cartes si besoin), puis choisis-la ci-dessous.`nElle est seulement LUE : rien n'y est jamais écrit. Une copie est gardée dans tes Documents."
        $go.Text = T "Read the Jooki's card" "Lire la carte du Jooki"
    } elseif ($state.step -eq 2) {
        $title.Text = T "2. The new, bigger card" "2. La nouvelle carte, plus grande"
        $text.Text = T "Take out the Jooki's card (keep it safe: it is your way back) and put the NEW card in, then click Refresh and choose it.`nEverything on the new card will be erased." "Retire la carte du Jooki (garde-la précieusement : c'est ton retour en arrière) et mets la NOUVELLE carte, puis clique sur Actualiser et choisis-la.`nTout ce qui est sur la nouvelle carte sera effacé."
        $go.Text = T "Write and enlarge the new card" "Écrire et agrandir la nouvelle carte"
    } else {
        $title.Text = T "3. Done!" "3. C'est prêt !"
        $text.Text = T "Put the new card in the Jooki and switch it on. At the first start it uses all the space by itself (it can take a minute longer).`nIf anything goes wrong, just put the old card back." "Mets la nouvelle carte dans le Jooki et allume-le. Au premier démarrage, il utilise tout l'espace tout seul (ça peut prendre une minute de plus).`nEn cas de souci, remets simplement l'ancienne carte."
        $go.Text = T "Close" "Fermer"; $combo.Enabled = $false; $refresh.Enabled = $false
    }
}

$refresh.Add_Click({ Fill-Cards })
$go.Add_Click({
    if ($state.step -eq 3) { $form.Close(); return }
    $sel = $combo.SelectedItem
    if (-not $sel) { return }
    $d = $sel.Disk
    $go.Enabled = $false; $refresh.Enabled = $false; $combo.Enabled = $false
    try {
        if ($state.step -eq 1) {
            $dir = [Environment]::GetFolderPath('MyDocuments')
            $free = (New-Object IO.DriveInfo ([IO.Path]::GetPathRoot($dir))).AvailableFreeSpace
            if ($free -lt $d.Size + 500MB) { throw (Fmt (T "Not enough free space in Documents: {0:N1} GB needed." "Pas assez de place dans Documents : il faut {0:N1} Go.") (($d.Size + 500MB) / 1e9)) }
            $state.image = Join-Path $dir ("Jooki-card-{0:yyyyMMdd-HHmm}.img" -f (Get-Date))
            Read-Card $d.Number $d.Size $state.image $progress $status
            $state.srcBytes = $d.Size; $state.step = 2
        } else {
            if ($d.Size -le $state.srcBytes) { throw (T "This card is not bigger than the Jooki's card. Choose the NEW card." "Cette carte n'est pas plus grande que celle du Jooki. Choisis la NOUVELLE carte.") }
            $ok = [Windows.Forms.MessageBox]::Show(((T "Erase EVERYTHING on this card?`n`n{0}" "Effacer TOUT le contenu de cette carte ?`n`n{0}") -f (Label-Of $d)), $form.Text, 'YesNo', 'Warning')
            if ($ok -ne 'Yes') { return }
            Write-CardToDisk $d.Number $d.Size $state.image $progress $status | Out-Null
            $state.step = 3
        }
        Show-Step
    } catch {
        [Windows.Forms.MessageBox]::Show(((T "It did not work: {0}`n`nNothing was written on the Jooki's card." "Ça n'a pas marché : {0}`n`nRien n'a été écrit sur la carte du Jooki.") -f $_.Exception.Message), $form.Text, 'OK', 'Error') | Out-Null
        Show-Step
    } finally {
        if ($state.step -ne 3) { $refresh.Enabled = $true; $combo.Enabled = $true; Fill-Cards }
        else { $go.Enabled = $true }
    }
})

Show-Step; Fill-Cards
if ($env:JOOKI_SD_PREVIEW) {   # docs/bench: draw the window into a picture, then close (reads and writes nothing)
    $form.Add_Shown({
        [Windows.Forms.Application]::DoEvents()
        $bmp = New-Object Drawing.Bitmap($form.Width, $form.Height)
        $form.DrawToBitmap($bmp, (New-Object Drawing.Rectangle(0, 0, $form.Width, $form.Height)))
        $bmp.Save($env:JOOKI_SD_PREVIEW); $form.Close()
    })
}
[void]$form.ShowDialog()
