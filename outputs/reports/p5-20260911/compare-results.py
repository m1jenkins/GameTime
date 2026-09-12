import json,pathlib,hashlib
root=pathlib.Path('/private/tmp/gametime-p5-20260911');results={}
for name in ['work','history_order','projections']:
 a=json.loads((root/'before-final'/(name+'-result.json')).read_text());b=json.loads((root/'after-final'/(name+'-result.json')).read_text());assert a==b,name
 results[name]={'equal':True,'sha256':hashlib.sha256(json.dumps(a,sort_keys=True).encode()).hexdigest(),'items':len(a)}
(root/'equivalence.json').write_text(json.dumps(results,indent=2));print(json.dumps(results,indent=2))
