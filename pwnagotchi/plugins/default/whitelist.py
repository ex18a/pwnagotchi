import os
import logging
import pwnagotchi
import pwnagotchi.plugins as plugins

class Whitelist(plugins.Plugin):
    __author__ = 'ex18a'
    __version__ = '2.1.0'
    __description__ = 'Scans handshakes for validated pairs, writes to /root/whitelist, and injects to runtime.'

    def __init__(self):
        self.original_whitelist = []
        self.whitelist_path = '/root/whitelist'
        self.handshake_dir = '/root/handshakes/'

    def on_loaded(self):
        # Ensure the file exists right at boot time
        self._ensure_whitelist_file_exists()

        # Capture the vanilla config state to revert safely on unload
        self.original_whitelist = list(pwnagotchi.config['main']['whitelist'])
        logging.info(f"[whitelist] Loaded. Original whitelist size: {len(self.original_whitelist)}")
        self._process_and_sync()

    def on_epoch(self, agent, epoch_data):
        self._process_and_sync()

    def on_sleep(self, agent, t):
        self._process_and_sync()

    def _ensure_whitelist_file_exists(self):
        try:
            if not os.path.exists(self.whitelist_path):
                open(self.whitelist_path, 'a').close()
                os.chmod(self.whitelist_path, 0o666)
                logging.info(f"[whitelist] Created missing whitelist file at {self.whitelist_path}")
        except Exception as e:
            logging.error(f"[whitelist] Error creating whitelist file: {e}")

    def _process_and_sync(self):
        # 1. Scan the folder and build the physical text file
        self._scan_handshakes_for_whitelist()
        # 2. Inject whatever is inside that text file into memory
        self._inject_into_runtime()

    def _scan_handshakes_for_whitelist(self):
        if not os.path.exists(self.handshake_dir):
            return

        # Look for valid pairs (.pcap + .22000)
        for filename in os.listdir(self.handshake_dir):
            if filename.endswith('.22000'):
                pcap_file = filename.replace('.22000', '.pcap')
                if os.path.exists(os.path.join(self.handshake_dir, pcap_file)):
                    self._extract_and_append_mac(filename)

    def _extract_and_append_mac(self, hash_filename):
        try:
            # Extract MAC from filename structure: Name_MAC.22000
            clean_name = hash_filename.replace('.22000', '')
            parts = clean_name.split('_')
            if len(parts) >= 2:
                raw_mac = parts[-1].lower()
                if len(raw_mac) == 12:
                    formatted_mac = ":".join(raw_mac[i:i+2] for i in range(0, 12, 2))

                    self._ensure_whitelist_file_exists()

                    # Read and check if already documented
                    with open(self.whitelist_path, 'r') as f:
                        lines = f.read().splitlines()

                    if formatted_mac not in lines:
                        with open(self.whitelist_path, 'a') as f:
                            f.write(f"{formatted_mac}\n")
                        logging.info(f"[whitelist] Logged new verified MAC: {formatted_mac}")
        except Exception as e:
            logging.error(f"[whitelist] MAC Extraction error: {e}")

    def _inject_into_runtime(self):
        self._ensure_whitelist_file_exists()

        try:
            with open(self.whitelist_path, 'r') as f:
                external_macs = [line.strip().lower() for line in f if line.strip()]

            if external_macs:
                current_config = pwnagotchi.config['main']['whitelist']
                added_count = 0
                for mac in external_macs:
                    if mac not in current_config:
                        current_config.append(mac)
                        added_count += 1

                if added_count > 0:
                    logging.info(f"[whitelist] Injected {added_count} new MACs into runtime.")
        except Exception as e:
            logging.error(f"[whitelist] Sync error: {e}")

    def on_unload(self, ui):
        logging.info("[whitelist] Restoring original whitelist...")
        pwnagotchi.config['main']['whitelist'] = list(self.original_whitelist)
