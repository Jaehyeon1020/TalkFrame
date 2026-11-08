import Foundation

enum TalkFrame {
    static let host = "serv.ds.kakao.com"
    static let address = "127.84.11.2"
    static let label = "local.talkframe.server"
    static let directory = "/Library/Application Support/TalkFrame"
    static let runtime = directory + "/Content/banner.json"
    static let certificate = directory + "/cert.der"
}

enum ImageFit: String, Codable, CaseIterable, Identifiable {
    case contain, cover
    var id: String { rawValue }
    var title: String { self == .contain ? "전체 표시" : "영역 채우기" }
}

struct Banner: Codable {
    let accessToken: String
    let revision: String
    let imageBase64: String
    let fit: ImageFit
    var imageData: Data? { Data(base64Encoded: imageBase64) }

    func validate() throws {
        guard UUID(uuidString: revision) != nil, UUID(uuidString: accessToken) != nil,
              let data = imageData, data.count <= 3_000_000,
              data.starts(with: [0xff, 0xd8, 0xff]) else {
            throw NSError(domain: "TalkFrame", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "올바른 JPEG 이미지 설정이 아닙니다."])
        }
    }

    static func load(_ path: String) throws -> Banner {
        let url = URL(fileURLWithPath: path)
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 4_100_000 else { throw CocoaError(.fileReadTooLarge) }
        let value = try JSONDecoder().decode(Banner.self, from: Data(contentsOf: url))
        try value.validate()
        return value
    }

    func html() -> String {
        // Only validated base64 and enum values enter the HTML. No user-supplied markup.
        """
        <!doctype html><html><head><meta charset="utf-8">
        <meta name="viewport" content="width=device-width,initial-scale=1">
        <style>:root{color-scheme:light dark}html,body{margin:0;width:100%;height:100%;overflow:hidden;background:#222}
        @media(prefers-color-scheme:light){html,body{background:#fff}}
        img{display:block;width:100%;height:100%;object-fit:\(fit.rawValue);pointer-events:none}</style>
        </head><body><img id="picture" alt="내가 선택한 이미지" src="data:image/jpeg;base64,\(imageBase64)">
        <script>
        (()=>{
          const picture=document.getElementById('picture');
          let revision='\(revision)';
          const loaded=()=>{try{window.chrome?.webview?.postMessage({event:{name:'AdLoaded',data:{result:true}}})}catch(e){}};
          window.chrome?.webview?.addEventListener('message',message=>{
            if(message.data?.event?.name==='ReadyToListen') loaded();
          });
          let busy=false;
          setInterval(async()=>{
            if(busy) return; busy=true;
            try{
              const response=await fetch('https://serv.ds.kakao.com/talkframe/state?key=\(accessToken)&w='+Math.round(window.innerWidth)+'&h='+Math.round(window.innerHeight),{cache:'no-store',credentials:'omit'});
              if(!response.ok) return;
              const state=await response.json();
              if(state.revision!==revision){
                const next=new Image();
                next.onload=()=>{picture.src=next.src;picture.style.objectFit=state.fit;revision=state.revision};
                next.src='https://serv.ds.kakao.com/talkframe/image?key=\(accessToken)&v='+encodeURIComponent(state.revision);
              }
            }catch(e){}finally{busy=false}
          },2000);
        })();
        </script></body></html>
        """
    }

    func adResponse() throws -> Data {
        let randomID = { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }
        let ad: [String: Any] = [
            "content": html(), "mimeType": "text/html", "width": 400, "height": 100,
            "type": "banner", "dspId": "MOMENT", "bidId": randomID(),
            "etxId": "MOMENT:conversion_id:" + randomID(),
            "cid": "120001", "crid": "12000001", "adid": "1200001",
            "feedback": [
                "feedbacklinks": ["https://serv.ds.kakao.com/talkframe/feedback"],
                "optoutpage": "https://serv.ds.kakao.com/talkframe/feedback",
                "reportpage": "https://serv.ds.kakao.com/talkframe/feedback"
            ]
        ]
        return try JSONSerialization.data(withJSONObject: [
            "status": "OK", "id": UUID().uuidString.lowercased(), "ads": [ad],
            "options": ["ext": ["refreshInterval": "60", "guaranteed": "N"], "allowFpc": "N"]
        ])
    }
}
