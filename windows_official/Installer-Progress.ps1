# ----------- Initialize-InstallerSpinner ----------
function Initialize-InstallerSpinner {
    # A WinForms timer animates independently of log polling; all painting stays on the UI thread.
    if ('StoryTold.Spinner' -as [type]) { return }
    Add-Type -ReferencedAssemblies System.Windows.Forms,System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Windows.Forms;
namespace StoryTold {
    public sealed class Spinner : Control {
        private readonly Timer timer;
        private float angle;
        // ----------- Spinner ----------
        public Spinner() {
            SetStyle(ControlStyles.UserPaint | ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer, true);
            AccessibleName = "Operation in progress";
            AccessibleRole = AccessibleRole.Indicator;
            TabStop = false;
            timer = new Timer { Interval = 60 };
            timer.Tick += delegate { angle = (angle + 12) % 360; Invalidate(); };
        }
        // -----------------------------
        public bool Active {
            get { return timer.Enabled; }
            set { timer.Enabled = value; Visible = value; Invalidate(); }
        }
        // ----------- OnPaint ----------
        protected override void OnPaint(PaintEventArgs e) {
            base.OnPaint(e);
            e.Graphics.SmoothingMode = SmoothingMode.AntiAlias;
            float stroke = Math.Max(2.0f, Width / 11.0f);
            RectangleF ring = new RectangleF(stroke, stroke, Width - 2*stroke - 1, Height - 2*stroke - 1);
            using (Pen track = new Pen(Color.FromArgb(220,228,240), stroke)) e.Graphics.DrawEllipse(track, ring);
            for (int segment = 0; segment < 10; segment++) {
                using (Pen pen = new Pen(Color.FromArgb(40 + segment*21, 30,95,190), stroke)) {
                    pen.StartCap = LineCap.Round; pen.EndCap = LineCap.Round;
                    e.Graphics.DrawArc(pen, ring, angle + segment*22, 20);
                }
            }
        }
        // -----------------------------
        // ----------- Dispose ----------
        protected override void Dispose(bool disposing) {
            if (disposing) { timer.Stop(); timer.Dispose(); }
            base.Dispose(disposing);
        }
        // -----------------------------
    }
}
'@
}
# -----------------------------

# ----------- Read-InstallerEvents ----------
function Read-InstallerEvents {
    param([string]$Path)
    # Read only appended complete UTF-8 lines. A partially written final line is retried.
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $stream = [IO.File]::Open($Path,'Open','Read','ReadWrite')
    try {
        if ($stream.Length -lt $script:eventOffset) { throw 'The operation log was unexpectedly truncated.' }
        $stream.Position = $script:eventOffset
        $buffer = New-Object byte[] 65536
        $count = $stream.Read($buffer,0,$buffer.Length)
        $last = $count - 1
        while ($last -ge 0 -and $buffer[$last] -ne 10) { $last-- }
        if ($last -lt 0) {
            if ($count -eq $buffer.Length) { throw 'An operation log entry exceeds the supported size.' }
            return
        }
        $text = [Text.Encoding]::UTF8.GetString($buffer,0,$last+1).TrimStart([char]0xFEFF)
        foreach ($line in ($text -split "`n")) {
            if ($line.Trim()) { $line | ConvertFrom-Json -ErrorAction Stop }
        }
        $script:eventOffset += $last + 1
    }
    finally { $stream.Dispose() }
}
# -----------------------------
