"""Repository-specific CI helper. Credentials stay in memory; never log headers.

Uses the user's existing Git Credential Manager login. publish imports exact Git
objects through GitHub's API when a proxy cannot transport git-receive-pack.
It refuses hash changes and never force-updates a branch.
"""
import argparse
import base64
import concurrent.futures
import datetime
import http.client
import time
import json
import io
import zipfile
import plistlib
import hashlib
import os
import re
import subprocess
import urllib.error
import urllib.request

REPO = "wenna/pickt"

class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,request,fp,code,msg,headers,newurl):
        redirected=super().redirect_request(request,fp,code,msg,headers,newurl)
        if redirected is not None and urllib.parse.urlparse(newurl).netloc != "api.github.com":
            redirected.remove_header("Authorization")
        return redirected

def git(*args):
    return subprocess.check_output(["git", *args])

def login():
    env = dict(os.environ, GIT_TERMINAL_PROMPT="0", GCM_INTERACTIVE="Never")
    result = subprocess.run(["git", "credential", "fill"], input="protocol=https\nhost=github.com\nusername=wenna\n\n", text=True, capture_output=True, env=env, timeout=20)
    fields = dict(line.split("=", 1) for line in result.stdout.splitlines() if "=" in line)
    if not fields.get("password"):
        raise RuntimeError("GitHub login unavailable; sign in using Git Credential Manager")
    return "Basic " + base64.b64encode((fields.get("username", "wenna") + ":" + fields["password"]).encode()).decode()

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("action", choices=["status", "logs", "publish", "dispatch", "artifacts"])
    parser.add_argument("--ref", default="HEAD")
    parser.add_argument("--branch", default="feat/native-mvp")
    parser.add_argument("--run", type=int)
    args = parser.parse_args()
    auth = login()
    opener=urllib.request.build_opener(SafeRedirect())
    def api(path, data=None, method=None, raw=False):
        request = urllib.request.Request("https://api.github.com/repos/" + REPO + path,
            data=None if data is None else json.dumps(data).encode(), method=method,
            headers={"Authorization": auth, "User-Agent": "Pickt-CI", "Accept": "application/vnd.github+json", "Content-Type": "application/json"})
        # urllib uses the existing Windows Internet Settings proxy; no global change.
        for attempt in range(3):
            try:
                with opener.open(request, timeout=25) as response:
                    body=response.read()
                return body if raw else json.loads(body)
            except (urllib.error.URLError, http.client.RemoteDisconnected, TimeoutError):
                if attempt==2: raise
                time.sleep(1+attempt)

    if args.action == "dispatch":
        api("/actions/workflows/ios.yml/dispatches",{"ref":args.branch},raw=True)
        print("DISPATCHED",args.branch)
        return
    if args.action == "status":
        runs=api("/actions/runs?branch="+args.branch+"&per_page=4")["workflow_runs"]
        print(json.dumps([{k:r[k] for k in ["id","status","conclusion","head_sha","html_url"]} for r in runs], indent=2))
        return
    if args.action == "artifacts":
        if not args.run: parser.error("--run is required")
        artifacts=api(f"/actions/runs/{args.run}/artifacts")["artifacts"]
        for item in artifacts:
            print("ARTIFACT",item["id"],item["name"],item["size_in_bytes"],"expired",item["expired"])
            if item["expired"]: continue
            archive=zipfile.ZipFile(io.BytesIO(api(f'/actions/artifacts/{item["id"]}/zip',raw=True)))
            if item['name']=='Pickt-simulator-preview':
                from pathlib import Path
                dest=Path('.local-data/ci');dest.mkdir(parents=True,exist_ok=True)
                for name in archive.namelist():
                    if name.endswith('.png'):
                        path=dest/Path(name).name
                        path.write_bytes(archive.read(name))
                        print('SCREENSHOT',str(path.resolve()))
                continue
            ipa=next(name for name in archive.namelist() if name.endswith('.ipa'))
            binary=archive.read(ipa)
            digest=hashlib.sha256(binary).hexdigest()
            expected=archive.read('SHA256SUMS.txt').decode().split()[0]
            if digest!=expected: raise RuntimeError("IPA checksum mismatch")
            app=zipfile.ZipFile(io.BytesIO(binary))
            info=plistlib.loads(app.read('Payload/Pickt.app/Info.plist'))
            if info['MinimumOSVersion']!='15.5': raise RuntimeError('Unexpected deployment target')
            print("VERIFIED",digest,info['CFBundleIdentifier'],info['CFBundleShortVersionString'],"iOS",info['MinimumOSVersion'])
            print(archive.read('BUILD.txt').decode())
        return
    if args.action == "logs":
        if not args.run: parser.error("--run is required")
        jobs=api(f"/actions/runs/{args.run}/jobs")["jobs"]
        for job in jobs:
            print("JOB",job["id"],job["name"],job["conclusion"])
            print("STEPS",[(s["name"],s["status"],s["conclusion"]) for s in job["steps"]])
            if job["conclusion"] == "failure":
                checkid=job["check_run_url"].rsplit("/",1)[-1]
                for annotation in api("/check-runs/"+checkid+"/annotations"):
                    print(annotation.get("message","")[:12000])
                text=api(f'/actions/jobs/{job["id"]}/logs',raw=True).decode("utf-8",errors="replace")
                lines=text.splitlines()
                print("\n".join(line for line in lines if "error:" in line.lower() or "failed" in line.lower())[-10000:])
        return

    if git("remote","get-url","origin").decode().strip() != "https://github.com/wenna/pickt.git":
        raise RuntimeError("Unexpected origin; refusing publication")
    target=git("rev-parse",args.ref).decode().strip()
    remote=api("/git/ref/heads/main")["object"]["sha"]
    commits=git("rev-list","--reverse","--topo-order",target,"^"+remote).decode().splitlines()
    cache=set()
    for commit in commits:
        try:
            api("/git/commits/"+commit)
            print("EXISTS",commit[:7],flush=True)
            # Known local trees have the exact SHA already verified on GitHub.
            cache.update(line.split()[2].decode() for line in git("ls-tree","-r",commit).splitlines() if line.split()[1]==b"blob")
            continue
        except urllib.error.HTTPError as error:
            if error.code != 404: raise
        records=[]
        for entry in git("ls-tree","-rz",commit).split(b"\0"):
            if not entry: continue
            meta,path=entry.split(b"\t",1)
            mode,kind,sha=meta.decode().split()
            if kind != "blob": raise RuntimeError("Submodules are unsupported")
            records.append({"path":path.decode(),"mode":mode,"type":"blob","sha":sha})
        unique={item["sha"] for item in records}-cache
        def blob(sha):
            content=git("cat-file","blob",sha)
            actual=api("/git/blobs",{"content":base64.b64encode(content).decode(),"encoding":"base64"})["sha"]
            if actual!=sha: raise RuntimeError("Blob hash changed")
            return sha
        with concurrent.futures.ThreadPoolExecutor(max_workers=1) as pool:
            cache.update(pool.map(blob,unique))
        tree=api("/git/trees",{"tree":records})["sha"]
        expected=git("rev-parse",commit+"^{tree}").decode().strip()
        if tree!=expected: raise RuntimeError("Tree hash changed")
        raw=git("cat-file","commit",commit).decode()
        header,message=raw.split("\n\n",1)
        def identity(kind):
            match=re.search(r"^"+kind+r" (.*) <([^>]+)> (\d+) ([+-]\d{4})$",header,re.M)
            if not match: raise RuntimeError("Unsupported commit identity")
            name,email,stamp,offset=match.groups()
            seconds=(int(offset[1:3])*60+int(offset[3:]))*60*(1 if offset[0]=="+" else -1)
            zone=datetime.timezone(datetime.timedelta(seconds=seconds))
            return {"name":name,"email":email,"date":datetime.datetime.fromtimestamp(int(stamp),zone).isoformat()}
        parents=re.findall(r"^parent (.*)$",header,re.M)
        actual=api("/git/commits",{"message":message,"tree":tree,"parents":parents,"author":identity("author"),"committer":identity("committer")})["sha"]
        if actual!=commit: raise RuntimeError("Commit hash changed; no branch was updated")
        print("IMPORTED",commit[:7],flush=True)
    path="/git/refs/heads/"+args.branch
    try:
        api("/git/ref/heads/"+args.branch)
        exists=True
    except urllib.error.HTTPError as error:
        if error.code != 404: raise
        exists=False
    if exists:
        api(path,{"sha":target,"force":False},method="PATCH")
    else:
        api("/git/refs",{"ref":"refs/heads/"+args.branch,"sha":target})
    print("PUBLISHED",args.branch,target,flush=True)

if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as error:
        print("GitHub API HTTP",error.code,"(no credential or headers logged)")
        raise SystemExit(1)
    except Exception as error:
        print(type(error).__name__,str(error))
        raise SystemExit(1)
