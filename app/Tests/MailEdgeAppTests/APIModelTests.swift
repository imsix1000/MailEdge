import Foundation
import Testing

@testable import MailEdgeApp

@Test func normalizesServerURL() {
  #expect(
    APIClient.normalizeServerURL("  https://mail.example.com/// ") == "https://mail.example.com")
}

@Test func canonicalizesWorkerURLAndRejectsRemoteHTTP() throws {
  let worker = try APIClient.validatedServerURL(" https://mail.example.com/login?from=web#inbox ")
  #expect(worker.absoluteString == "https://mail.example.com")

  let local = try APIClient.validatedServerURL("http://127.0.0.1:8787/")
  #expect(local.absoluteString == "http://127.0.0.1:8787")

  #expect(throws: APIClientError.insecureServerURL) {
    try APIClient.validatedServerURL("http://mail.example.com")
  }
}

@Test func decodesMessageListResponse() throws {
  let json = #"""
    {
      "items": [{
        "id": "msg_1",
        "mailboxId": "mb_1",
        "mailboxAddress": "hello@example.com",
        "internalId": null,
        "direction": "inbound",
        "folder": "inbox",
        "subject": "Welcome",
        "snippet": "Hello from MailEdge",
        "from": {"email": "sender@example.net", "name": "Sender"},
        "to": [{"email": "hello@example.com"}],
        "isRead": false,
        "isStarred": false,
        "hasAttachments": false,
        "status": null,
        "provider": null,
        "category": "updates",
        "receivedAt": "2026-08-23T08:00:00.000Z"
      }],
      "nextCursor": null
    }
    """#
  let response = try JSONDecoder().decode(MessagesResponse.self, from: Data(json.utf8))
  #expect(response.items.count == 1)
  #expect(response.items[0].participant == "Sender")
  #expect(response.items[0].inboundAlias == nil)
  #expect(response.items[0].receivedDate != nil)
}

@Test func showsCatchAllAliasWhenEnvelopeRecipientDiffers() throws {
  let json = #"""
    {
      "items": [{
        "id": "msg_2",
        "mailboxId": "mb_1",
        "mailboxAddress": "inbox@example.com",
        "internalId": null,
        "direction": "inbound",
        "folder": "inbox",
        "subject": "Alias",
        "snippet": "Catch-all",
        "from": {"email": "sender@example.net"},
        "to": [{"email": "random@example.com"}],
        "isRead": true,
        "isStarred": false,
        "hasAttachments": false,
        "status": null,
        "provider": null,
        "category": null,
        "receivedAt": "2026-09-16T08:00:00.000Z"
      }],
      "nextCursor": null
    }
    """#
  let response = try JSONDecoder().decode(MessagesResponse.self, from: Data(json.utf8))
  #expect(response.items[0].inboundAlias == "random@example.com")
}

@Test func decodesContactsResponse() throws {
  let json = #"""
    {
      "contacts": [{
        "id": "contact_1",
        "email": "alex@example.com",
        "name": "Alex Chen",
        "company": "Example",
        "notes": null,
        "createdAt": "2026-08-23T08:00:00.000Z",
        "updatedAt": "2026-08-23T08:00:00.000Z"
      }]
    }
    """#
  let response = try JSONDecoder().decode(ContactsResponse.self, from: Data(json.utf8))
  #expect(response.contacts.count == 1)
  #expect(response.contacts[0].email == "alex@example.com")
  #expect(response.contacts[0].initials == "A")
}
