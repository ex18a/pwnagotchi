import os
import logging
import pwnagotchi
import pwnagotchi.plugins as plugins

class ExternalWhitelist(plugins.Plugin):
    __author__ = 'ex18a'
    __version__ = '1.3.0'
    __description__ = 'Forces /root/whitelist into the Pwnagotchi config at runtime and restores on unload.'

    def __init__(self):
        # Stores the original config.toml list to revert later
        self.original_whitelist = []

    def on_loaded(self):
        # Capture the state of the whitelist BEFORE we modify it
        self.original_whitelist = list(pwnagotchi.config['main']['whitelist'])
        logging.info(f"[external_whitelist] Loaded. Original whitelist size: {len(self.original_whitelist)}")
        self.sync_whitelist()

    def on_epoch(self, agent, epoch_data):
        self.sync_whitelist()

    def on_sleep(self, agent, t):
        # Match cleaner.py's heartbeat behavior exactly
        self.sync_whitelist()

    def sync_whitelist(self):
        whitelist_path = '/root/whitelist'
        if not os.path.exists(whitelist_path):
            return

        try:
            with open(whitelist_path, 'r') as f:
                external_macs = [line.strip().lower() for line in f if line.strip()]

            if external_macs:
                current_config = pwnagotchi.config['main']['whitelist']
                added_count = 0
                for mac in external_macs:
                    if mac not in current_config:
                        current_config.append(mac)
                        added_count += 1

                if added_count > 0:
                    logging.info(f"[external_whitelist] Injected {added_count} new MACs into runtime.")
        except Exception as e:
            logging.error(f"[external_whitelist] Sync error: {e}")

    def on_unload(self, ui):
        logging.info("[external_whitelist] Restoring original whitelist...")
        # Wipes the runtime memory back to your default config
        pwnagotchi.config['main']['whitelist'] = list(self.original_whitelist)
