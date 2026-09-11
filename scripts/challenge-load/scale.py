#!/usr/bin/env python3
"""Expand this owned 2k corpus to 25k and issue a new independently bound preflight."""
from __future__ import annotations
import argparse,json
from lab import Lab,save,digest
from fixtures import accounts
from oracles import load_live,check_preflight,refresh_live_metadata,write_preflight,history_hash,require

def expand(lab):
    live=load_live(lab)
    if live['accounts']!=2000:raise ValueError('only a verified 2000->25000 expansion is supported')
    previous=check_preflight(lab,live)
    accounts(lab,25000)
    expanded_hashes=history_hash(lab)
    same_history=expanded_hashes==previous['history_hashes']
    save(lab.data/'tier-history-comparison.json',{'passed':same_history,'before_accounts':2000,'after_accounts':25000,
      'before_receipt_sha256':digest(lab.data/'preflight-2000.json'),
      'before_history_hashes':previous['history_hashes'],'after_history_hashes':expanded_hashes,
      'publication_order':'comparison precedes new live metadata and admissible 25000 preflight'})
    require(same_history,'expansion_preserves_2000_history')
    refreshed=refresh_live_metadata(lab,live,25000)
    receipt=write_preflight(lab,refreshed)
    print(json.dumps({'accounts':receipt['accounts'],'checks':receipt['checks'],'passed':receipt['passed']}))
    return receipt

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('run_root')
    args=parser.parse_args();expand(Lab(args.run_root))

if __name__=='__main__':main()
