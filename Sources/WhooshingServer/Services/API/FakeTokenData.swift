import Foundation
@preconcurrency import AnyCodable

public extension Api.Debuging {
    static let credential = "0rZ5GsQqysbOvm/Ya7+QhA=="
    static let token = "4r0MHtw29zNz+DfyDo8Bzvn02kyoewqYNndSo38AuLY="
    
    static let tokenId = UUID(uuidString: "F387F90B-5E1B-44DF-A2CD-67F3C3AA2BC1")!
    static let userId = UUID(uuidString: "8FB83B07-7FA3-4954-A981-BA35AF74653C")!
    static let infoId = UUID(uuidString: "BE3BCBE7-B127-49DC-9752-BBD0E00D01C1")!
    static let emailIds = [UUID(uuidString: "A7851C53-B49C-403B-A7AA-825D71158304")!]
    static let phoneIds = [UUID(uuidString: "242BE4E2-9A6E-4D7C-A3F2-0742F91EF3F1")!, UUID(uuidString: "91596272-EF53-4104-B0BD-1C6A68A80FF4")!]
    
    static let emails = ["testing@fake.gmail.com"]
    static let phones = ["1234567890921", "8319210398123"]
    
    static let fakeTokenData: [String: AnyCodable] = {
        [
            "id": AnyCodable(tokenId),
            "user_id": AnyCodable(userId),
            "credential": AnyCodable(credential),
            "token": AnyCodable(token),
            "valid": true,
            "expire_after": AnyCodable(7 * 24 * 60),
            "created_at": AnyCodable(Date()),
            "user": [
                "id": userId,
                "loaded": true,
                "value": [
                    "id": userId,
                    "email": "user@testing.com",
                    "created_at": Date(),
                    "updated_at": Date(),
                    "info": [
                        "loaded": true,
                        "value": [
                            "id": infoId,
                            "user_id": userId,
                            "nickname": "Hello World",
                            "identifier": "FAKE0392818203815",
                            "birthday": Date(),
                            "created_at": Date(),
                            "updated_at": Date(),
                            "user": [
                                "loaded": false,
                                "value": nil
                            ],
                            "alternate_emails": [
                                "loaded": true,
                                "value": [
                                    [
                                        "id": emailIds[0],
                                        "value": emails[0],
                                        "order": UInt16(0),
                                        "summary": "the secondary email address",
                                        "created_at": Date(),
                                        "updated_at": Date(),
                                        "user_info_id": infoId,
                                        "user_info": [
                                            "loaded": false,
                                            "value": nil
                                        ]
                                    ]
                                ]
                            ],
                            "phones": [
                                "loaded": true,
                                "value": [
                                    [
                                        "id": phoneIds[0],
                                        "value": phones[0],
                                        "order": UInt16(0),
                                        "summary": "my personal phone number",
                                        "created_at": Date(),
                                        "updated_at": Date(),
                                        "user_info_id": infoId,
                                        "user_info": [
                                            "loaded": false,
                                            "value": nil
                                        ]
                                    ], [
                                        "id": phoneIds[1],
                                        "value": phones[1],
                                        "order": UInt16(1),
                                        "summary": "placeholder phone number",
                                        "created_at": Date(),
                                        "updated_at": Date(),
                                        "user_info_id": infoId,
                                        "user_info": [
                                            "loaded": false,
                                            "value": nil
                                        ]
                                    ]
                                ]
                            ],
                            "addresses": [
                                "loaded": true,
                                "value": []
                            ]
                        ]
                    ],
                    "token": [
                        "loaded": false,
                        "value": nil
                    ],
                    "groups": [
                        "loaded": false,
                        "value": nil,
                        "ids_loaded": false,
                        "ids": nil
                    ],
                    "roles": [
                        "loaded": false,
                        "value": nil,
                        "ids_loaded": false,
                        "ids": nil
                    ],
                    "domains": [
                        "loaded": false,
                        "value": nil,
                        "ids_loaded": false,
                        "ids": nil
                    ]
                ]
            ]
        ]
    }()
}
