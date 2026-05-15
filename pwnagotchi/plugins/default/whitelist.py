import os
import logging
import pwnagotchi
import pwnagotchi.plugins as plugins

class Whitelist(plugins.Plugin):
    __author__ = 'ex18a'
    __version__ = '1.6.0'
    __description__ = 'Whitelists MACs if both .pcap and .22000 exist. run this with cleaner.py plugin.'
# this plugin is to stop pwnagotchi attacking networks it already has a full handshake file for.
# it checks for both pcap and 22000 files before adding to a whitelist file so running this with cleaner plugin is recommended.

    def __init__(self):
        self.original_whitelist = []
        self.whitelist_path = '/root/whitelist'
        self.handshake_dir = '/root/handshakes/'

    def on_loaded(self):
        self.original_whitelist = list(pwnagotchi.config['main']['whitelist'])
        logging.info(f"[whitelist] Loaded. Original whitelist size: {len(self.original_whitelist)}")
        self.sync_whitelist()

    def on_epoch(self, agent, epoch_data):
        self.sync_whitelist()

    def sync_whitelist(self):
        self._scan_handshakes_for_macs()

        if not os.path.exists(self.whitelist_path):
            return

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

    def _scan_handshakes_for_macs(self):
        if not os.path.exists(self.handshake_dir):
            return

        found_macs = set()
        for filename in os.listdir(self.handshake_dir):
            # use the .22000 file as the indicator of a successful crack/check
            if filename.endswith('.22000'):
                hash_path = os.path.join(self.handshake_dir, filename)
                pcap_path = os.path.join(self.handshake_dir, filename.replace('.22000', '.pcap'))

                # DOUBLE CHECK: Both files must exist to whitelist
                if os.path.exists(hash_path) and os.path.exists(pcap_path):
                    try:
                        clean_name = filename.replace('.22000', '')
                        parts = clean_name.split('_')
                        if len(parts) >= 2:
                            raw_mac = parts[-1].lower()
                            if len(raw_mac) == 12:
                                formatted_mac = ":".join(raw_mac[i:i+2] for i in range(0, 12, 2))
                                found_macs.add(formatted_mac)
                    except:
                        continue
                # If the .pcap is missing, we do nothing (leaving it off the whitelist)

        if found_macs:
            existing = []
            if os.path.exists(self.whitelist_path):
                with open(self.whitelist_path, 'r') as f:
                    existing = f.read().splitlines()

            with open(self.whitelist_path, 'a') as f:
                for mac in found_macs:
                    if mac not in existing:
                        f.write(f"{mac}\n")
                        logging.info(f"[whitelist] Verified Pair (.pcap + .22000) found for {mac}")

    def on_unload(self, ui):
        logging.info("[whitelist] Restoring original whitelist...")
        pwnagotchi.config['main']['whitelist'] = list(self.original_whitelist)
