# prompt with user, box name and folder (SSH and System -> Terminal)
[ -n "$PS1" ] && PS1='\u@\h:\w\$ '

# programs of system apps (nano, htop …), after the firmware's own
case ":$PATH:" in *:/opt/shareos/bin:*) ;; *) PATH="$PATH:/opt/shareos/bin" ;; esac
