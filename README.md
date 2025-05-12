# ☁️ Linux Log Monitoring & Alerting Lab – Linode Setup + Deception Environment

This project simulates a host-based intrusion detection system deployed on a cloud VPS (Linode). It centralizes logs, monitors suspicious SSH activity, and creates a fake internal environment to deceive attackers.

## 🧰 Requirements

- Linode VPS (Ubuntu recommended)
- SSH access and root privileges

---

## ⚙️ Step 1: Update & Install Dependencies

```bash
sudo apt update && sudo apt upgrade -y
sudo apt install rsyslog net-tools curl git ufw zip -y
```

---

## 📡 Step 2: Enable and Configure `rsyslog` (Server)

1. Edit `/etc/rsyslog.conf`:

```bash
sudo nano /etc/rsyslog.conf
```

2. Enable UDP/TCP reception:

```bash
module(load="imudp")
input(type="imudp" port="514")

module(load="imtcp")
input(type="imtcp" port="514")
```

3. Allow ports through firewall:

```bash
sudo ufw allow 514/tcp
sudo ufw allow 514/udp
sudo ufw enable
```

4. Restart rsyslog:

```bash
sudo systemctl restart rsyslog
```

---

## 🎯 Step 2.5: Set Up SSH Port Deception

To make the Cowrie honeypot more believable, configure the real SSH server to listen on a different port (e.g., 2224) and allow Cowrie to bind to port 22.

### 1. Change the OpenSSH port:

```bash
sudo nano /etc/ssh/sshd_config
```

Change:

```bash
Port 22
```

To:

```bash
Port 2224
```

Then restart SSH:

```bash
sudo systemctl restart ssh
```

> ⚠️ Make sure your Linode firewall allows port 2224 and you can reconnect before logging out!

### 2. Confirm Cowrie is configured to listen on port 22

Edit Cowrie config:

```bash
nano /opt/cowrie/etc/cowrie.cfg
```

Ensure the port is set:

```ini
[ssh]
listen_port = 22
```

Restart Cowrie:

```bash
sudo systemctl restart cowrie
```

---

## 🛠️ Step 3: Create SSH Activity Monitoring Script

1. Create the script where you'd like (example: `/home/(your_username)/cowrielogs.sh`):

```bash
nano /home/(your_username)/cowrielogs.sh
```

2. Paste the following:

````bash
#!/bin/bash

LOG_PATH="/opt/cowrie/var/log/cowrie/cowrie.log"
SHOW_COMMANDS_ONLY=false

# Handle argument
if [[ "$1" == "--commands-only" ]]; then
    SHOW_COMMANDS_ONLY=true
fi

# Colors
RED="\033[0;31m"
GREEN="\033[0;32m"
YELLOW="\033[1;33m"
BLUE="\033[0;34m"
CYAN="\033[0;36m"
NC="\033[0m" # No Color

echo -e "${CYAN}[*] Parsing and summarizing Cowrie sessions...${NC}"
if $SHOW_COMMANDS_ONLY; then
    echo -e "${YELLOW}[*] Showing only sessions where commands were executed.${NC}"
fi

# Parse log and store sessions
grep -E 'HoneyPotSSHTransport|login attempt|CMD:|Connection lost after' "$LOG_PATH" | awk -v showOnly="$SHOW_COMMANDS_ONLY" -v RED="$RED" -v GREEN="$GREEN" -v YELLOW="$YELLOW" -v BLUE="$BLUE" -v CYAN="$CYAN" -v NC="$NC" '
{
    if ($0 ~ /HoneyPotSSHTransport,[0-9]+,[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/) {
        match($0, /HoneyPotSSHTransport,[0-9]+,[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+/, arr)
        split(arr[0], parts, ",")
        session_id = parts[2]
        ip = parts[3]
        sessions[session_id]["ip"] = ip
    }
    if ($0 ~ /login attempt \[/) {
        match($0, /login attempt \[b.([^\/]*)\/b.([^]]*)/, creds)
        user = creds[1]
        pass = creds[2]
        sessions[session_id]["login"] = user "/" pass
        sessions[session_id]["start"] = substr($1, 1, 19)
    }
    if ($0 ~ /CMD:/) {
        cmd = substr($0, index($0, "CMD:") + 5)
        sessions[session_id]["cmds"] = sessions[session_id]["cmds"] cmd "\n"
    }
    if ($0 ~ /Connection lost after/) {
        match($0, /after ([0-9.]+) seconds/, t)
        sessions[session_id]["duration"] = t[1]
    }
}
END {
    for (id in sessions) {
        cmds = sessions[id]["cmds"]
        if (showOnly == "true" && length(cmds) == 0) {
            continue
        }

        print "\n" BLUE "------------------------ SESSION " id " ------------------------" NC
        print YELLOW "IP Address:  " NC sessions[id]["ip"]
        print YELLOW "Login:      " NC sessions[id]["login"]
        print YELLOW "Start Time: " NC sessions[id]["start"]
        print YELLOW "Duration:   " NC sessions[id]["duration"] " sec"
        print YELLOW "Commands:" NC

        if (length(cmds) > 0) {
            print GREEN cmds NC
        } else {
            print RED " No commands executed. " NC
        }
    }
}'
````

3. Make it executable:

```bash
chmod +x /home/(your_username)/cowrielogs.sh
```

4. Optional – keep it running even after logout:

```bash
nohup /home/(your_username)/cowrielogs.sh &
```

5. Optional – run it at every reboot:

```bash
sudo crontab -e
```

Add:

```bash
@reboot /home/(your_username)/cowrielogs.sh &
```

---

## 🎭 Step 4: Deception Layer – Fake Internal Environment

### 1. Fake `/etc/hosts` entries

```bash
sudo tee -a /etc/hosts > /dev/null <<EOL
10.0.1.10 vault.corp.internal
10.0.1.11 db01.corp.internal
10.0.1.12 backup.internal
EOL
```

### 2. Create fake user home directories

```bash
sudo mkdir -p /home/john /home/sarah /home/devops
sudo chown -R root:root /home/*
```

### 3. Populate with fake files

```bash
echo "Internal vault password: hunter2" | sudo tee /home/john/notes.txt
echo "Backup schedule: Sunday 3AM" | sudo tee /home/sarah/backup-plan.txt
echo "AWS_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE" | sudo tee /home/devops/aws-creds.txt
echo "BEGIN RSA PRIVATE KEY..." | sudo tee /home/devops/id_rsa
echo "root:x:0:0:root:/root:/bin/bash" | sudo tee /home/john/shadow.bak
echo "This is a secret internal memo. DO NOT SHARE." | sudo tee /home/sarah/memo.txt

mkdir -p /tmp/fakefiles
echo "Sensitive Financials Q4.pdf" > /tmp/fakefiles/report.txt
zip -r /home/john/financials_backup.zip /tmp/fakefiles
rm -r /tmp/fakefiles

sudo touch /home/devops/.bash_history
```

### 4. Fake cron jobs

```bash
echo "@daily /usr/local/bin/db-backup.sh" | sudo tee /etc/cron.d/fakejob
```

---

## 🔌 Step 5: Add Fake Commands to History

```bash
echo "ssh db01.corp.internal" >> ~/.bash_history
echo "cat /home/john/notes.txt" >> ~/.bash_history
echo "scp backup.tar.gz backup.internal:/mnt/backups/" >> ~/.bash_history
```

---

## ✅ Final Notes

- You now have a fully operational SSH honeypot with active deception and log monitoring.
- Tailor the fake environment endlessly for maximum attacker confusion and analysis potential.

---

## 💡 Bonus Tip

Pair this lab with Cowrie, ELK, Wazuh, or Discord webhook alerts for a full deception + detection stack.
