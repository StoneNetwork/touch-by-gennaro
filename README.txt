
Touch by Gennaro – Deploy Kit

1) Plaats je statische sitebestanden in de map 'site/' van je repo.
2) Installeer een self-hosted GitHub Actions runner op je WordPress-LXC (label: wp-lxc).
3) Gebruik de meegeleverde workflow (.github/workflows/deploy.yml).
4) Run de workflow of push naar main. De deploy zet /home/wpbot/site.zip en draait het idempotente script.
