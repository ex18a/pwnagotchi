import os
import logging
import subprocess
import time
import pwnagotchi.plugins as plugins

class Cleaner(plugins.Plugin):
    __author__ = 'ex18a'
    __version__ = '3.3.0'

    def __init__(self):
        self.handshake_dir = '/root/handshakes/'

    def on_loaded(self):
        logging.info("[cleaner] Janitor v3.3.0: PCAP verification active")
        self._startup_cleanup()

    def _startup_cleanup(self):
        if not os.path.exists(self.handshake_dir):
            return
        for filename in os.listdir(self.handshake_dir):
            if filename.endswith('.pcap'):
                self._attempt_valid_pcap(os.path.join(self.handshake_dir, filename))

    def on_sleep(self, agent, t):
        self._process_files()

    def _process_files(self):
        if not os.path.exists(self.handshake_dir):
            return
        for filename in os.listdir(self.handshake_dir):
            fullpath = os.path.join(self.handshake_dir, filename)
            if filename.endswith('.pcap'):
                if time.time() - os.path.getmtime(fullpath) > 10:
                    self._attempt_valid_pcap(fullpath)

    def _attempt_valid_pcap(self, pcap_path):
        filename = os.path.basename(pcap_path)
        output_hash = pcap_path.replace('.pcap', '.22000')

        if not os.path.exists(output_hash):
            subprocess.run(
                ['/usr/bin/hcxpcapngtool', '-o', output_hash, pcap_path],
                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
            )

        # If no hash exists after running tool, the PCAP is junk
        if not os.path.exists(output_hash) and os.path.exists(pcap_path):
            logging.info(f"[cleaner] Deleting junk PCAP: {filename}")
            try:
                os.remove(pcap_path)
            except:
                pass
