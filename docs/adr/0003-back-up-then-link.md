# A real file in the way is backed up, then linked over

Four policies existed for "something real is already at a managed target": back it up beside
itself, move it to a directory outside the checkout, refuse and warn, or overwrite. All four now
back up and then link, with the backup location a parameter.

Refusing was the most defensible of the four and is what `ai/install.sh` did. It was rejected
because it leaves the user stuck: the installer reports a problem, declines to fix it, and the
only way forward is to delete the file by hand — so the safe-looking policy is the one that
makes people delete things.

The location is a parameter rather than a constant because one of the four differences was
deliberate, not accidental: `deploy-secrets.ps1` backs up **outside** the checkout, so displaced
plaintext never sits somewhere it could be committed. That is a security property, and it is now
an argument and a test rather than a comment.

Nothing is ever deleted. A symlink in the way is replaced without a backup, because it holds no
content of its own.
