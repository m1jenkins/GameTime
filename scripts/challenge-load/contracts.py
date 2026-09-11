"""Independent expected agreement/evaluation oracles; no framework or database imports."""
UNITS={'steps':'whole_counts','exercise':'integer_seconds','distance':'integer_millimetres','timed':'whole_elapsed_seconds'}

def expected_terms(policy,config,participants,minimum,capacity,version=1):
    mode,metric,competition,_=policy.split('_')
    result={'policy':policy,'source':'fictional_'+metric+'_v1','mode':mode,'competition':competition,'metric':metric,'unit':UNITS[metric],
      'config':config,'simulation':'nonredeemable','review_hours':48,'resolution_hours':72,'minimum':minimum,
      'missing_rule':'void_if_any_unresolved' if competition=='leaderboard' else 'exclude_refund_minimum',
      'exit_rule':'exclude_refund_minimum','allocation_rule':'co_winners_split_active_pool_remainder_unallocated' if competition=='leaderboard' else 'return_qualifiers_split_misses_remainder_unallocated'}
    if mode=='community':
        result.update(common_target=100,capacity=capacity,settings_status='unapproved_fixture_only')
    else:
        result.update(version=version,participants=[{k:v for k,v in person.items() if v is not None} for person in sorted(participants,key=lambda p:p['actor_id'])],
          comparator=('minimum' if metric=='timed' else 'maximum') if competition=='leaderboard' else ('strict_less_than' if metric=='timed' else 'greater_or_equal'))
    return result

def allocation(policy,people,minimum,amount=100):
    """Integer arithmetic independently mirrors the frozen rules, including exclusion and ties."""
    mode,metric,competition,_=policy.split('_')
    active=[p for p in people if not p['excluded']]
    known=[p for p in active if p['state']=='complete']
    void=len(known)<minimum or (competition=='leaderboard' and len(known)!=len(active))
    if void:winners=[]
    elif competition=='leaderboard':
        best=(min if metric=='timed' else max)(p['value'] for p in known)
        winners=[p for p in known if p['value']==best]
    else:
        winners=[p for p in known if (p['value']<p['target'] if metric=='timed' else p['value']>=p['target'])]
    win_ids={p['actor_id'] for p in winners};known_ids={p['actor_id'] for p in known}
    result={};unallocated=0
    if not void:
        if competition=='leaderboard':unallocated=(len(active)*amount)%len(winners)
        elif winners:unallocated=((len(known)-len(winners))*amount)%len(winners)
        else:unallocated=len(known)*amount
    for person in people:
        key=person['actor_id']
        if void:state,returned='void',amount
        elif key not in known_ids:state,returned='excluded',amount
        elif key in win_ids:
            state='winner' if competition=='leaderboard' else 'met'
            returned=(len(active)*amount)//len(winners) if competition=='leaderboard' else amount+((len(known)-len(winners))*amount)//len(winners)
        else:state,returned=('placed' if competition=='leaderboard' else 'missed'),0
        result[key]={'status':state,'returned_cents':returned}
    return {'outcome':'void' if void else 'scored','participants':result,'entry_cents':len(people)*amount,'unallocated_cents':unallocated,'simulation':'nonredeemable'}
