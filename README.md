# SwiftData HistoryObserver Sync Demo

This project demonstrates how to use **SwiftData's `HistoryObserver`** to synchronize local data with a custom backend server.

The sample application stores room measurements locally using SwiftData. Whenever a room is added, updated, or deleted, `HistoryObserver` detects the change, converts it into a synchronization payload, and uploads it to a backend service.

This project accompanies my article on `HistoryObserver` and serves as a practical example of building synchronization with SwiftData. If you would like to dive deeper into SwiftData architecture, modeling, persistence, and advanced techniques, check out my **SwiftData Architecture** book:

📖 **SwiftData Architecture**
https://azamsharp.school/swiftdata-architecture.html

> **Note**
>
> `HistoryObserver` currently supports **one way synchronization**. It observes changes made to the local SwiftData store and allows those changes to be sent to a server. Changes made on the server are not automatically synchronized back to the client.


## Features

* SwiftData persistence
* SwiftData `HistoryObserver`
* Continuous observation using Swift Observation
* Incremental synchronization using `DefaultHistoryToken`
* Batched network requests
* Soft delete support
* Simple Node.js backend

## How It Works

The synchronization flow is straightforward.

1. The user creates, updates, or deletes a room.
2. SwiftData records the transaction.
3. `HistoryObserver` detects the new transaction.
4. `RoomSyncManager` fetches only the new transactions using the last processed token.
5. Transactions are converted into `RoomPayload` objects.
6. All payloads are uploaded to the backend in a single request.
7. After a successful upload, the latest history token is saved.
8. Soft deleted rooms are permanently removed from the local database.


## Running the iOS Application

### Requirements

* Xcode 27 or later
* iOS 27 SDK
* macOS Tahoe
* Swift 6

Build and run the application in Xcode.

## Sample Payload

```json
[
  {
    "id": "4D9B718D-B802-49EA-B2F4-D557E544588B",
    "name": "Kitchen",
    "area": 250,
    "action": "insert"
  },
  {
    "id": "B646399D-BCE4-4D8F-B2BB-568002FC6E03",
    "name": "Bedroom",
    "area": 300,
    "action": "update"
  }
]
```

For delete operations, only the identifier and action are required.

```json
{
    "id": "4D9B718D-B802-49EA-B2F4-D557E544588B",
    "action": "delete"
}
```

## Technologies

* SwiftUI
* SwiftData
* HistoryObserver
* Swift Observation
* Async/Await
* Node.js
* Express

## Learn More

This project accompanies my article on using **SwiftData HistoryObserver** to synchronize local data with a custom backend.

If you enjoy this project, consider giving it a ⭐ on GitHub.
