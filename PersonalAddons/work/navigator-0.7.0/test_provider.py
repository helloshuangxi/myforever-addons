import json
from http.server import BaseHTTPRequestHandler,HTTPServer
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        value=json.loads(self.rfile.read(int(self.headers["Content-Length"])))
        query=value["messages"][-1]["content"]
        data=json.loads(query)
        if data["questID"]:
            steps=[{"kind":"quest","key":c["key"],"text":c["name"]} for c in data["choices"]]
        else:
            steps=[{"kind":"place","term":"铁炉堡","text":"前往铁炉堡。"}]
        payload=json.dumps({"choices":[{"message":{"content":json.dumps({"steps":steps,"message":"问路回放"})}}]}).encode()
        self.send_response(200); self.send_header("Content-Length",str(len(payload)));self.end_headers();self.wfile.write(payload)
HTTPServer(("127.0.0.1",42813),Handler).serve_forever()
