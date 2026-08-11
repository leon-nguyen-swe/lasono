# Core Audio System — Implementation Plan

## 1. Phase Goal

The goal of Phase 1 is to build the first complete vertical slice of LaSono's core audio system.

At the end of this phase, the system should support the following flow:

```text
Upload a track
      ↓
Store the audio file
      ↓
Store track metadata
      ↓
Retrieve track information
      ↓
Stream the audio
      ↓
Play and seek the track in Flutter
```

### Definition of Done

Phase 1 is considered complete when a user can:

* Upload an audio file with track metadata.
* Store the audio file in the configured storage.
* Store the track metadata in PostgreSQL.
* Retrieve track information through the REST API.
* Stream the audio using HTTP Range Requests.
* Play the audio from the Flutter application.
* Seek to different positions during playback.
* Complete the entire flow from upload to playback successfully.

---

# 2. Architecture

## 2.1 System Architecture

LaSono uses a Flutter mobile application and a Spring Boot backend.

```text
                         LaSono
                            │
              ┌─────────────┴─────────────┐
              │                           │
           Flutter                   Spring Boot
              │                           │
              │         REST API          │
              └──────────────┬────────────┘
                             │
                       Track Module
                             │
          ┌──────────────────┼────────────────────────┐
          │                  │                        │
       Domain           Application            Infrastructure
          │                  │                        │
        Track         Upload / Get / Stream       Persistence
                                                  Audio Storage
                                                  Audio Streaming
```

The backend follows a Modular Monolith architecture with Clean Architecture inside each business module.

Phase 1 focuses only on the `track` module.

---

## 2.2 Track Module

The Track Module is responsible for the core audio workflow.

```text
Track Module
│
├── Track Domain
│
├── Track Application
│
├── Track Infrastructure
│   ├── Persistence
│   ├── Audio Storage
│   └── Audio Streaming
│
└── Track Presentation
```

### Main responsibilities

**Domain**

* Represent the Track business concept.
* Define track-related business rules.

**Application**

* Define and execute track use cases.
* Coordinate domain logic with required external capabilities.

**Infrastructure**

* Persist track data.
* Store audio files.
* Read audio data for streaming.

**Presentation**

* Expose Track REST APIs.
* Convert HTTP requests and responses.

---

## 2.3 Dependency Rules

The Track Module follows these dependency rules:

```text
  Presentation
       ↓
  Application
       ↓
    Domain
```

Infrastructure provides concrete implementations for the abstractions required by the application and domain layers.

The domain layer must not depend directly on:

* Spring Framework
* JPA
* PostgreSQL
* Local File System
* AWS S3
* HTTP

The purpose of these rules is to keep the core business logic independent from technical implementation details.

---

# 3. Domain and Data Model

## 3.1 Track Domain

The central business concept of Phase 1 is the `Track`.

The Track domain should contain the information required to represent an audio track.

The exact attributes will be decided during domain design.

Potential information includes:

```text
Track
├── id
├── title
├── description
├── duration
├── file information
└── timestamps
```

The domain model should contain only information and rules that belong to the Track business concept.

---

## 3.2 Track Metadata

Track metadata is stored separately from the audio binary data.

The metadata may include:

* Track ID
* Title
* Description
* Duration
* Audio file information
* Creation time
* Update time

The metadata is persisted in PostgreSQL.

The audio binary itself is not stored directly in PostgreSQL.

---

## 3.3 Persistence Model

The persistence model represents how Track information is stored in PostgreSQL.

The database schema will be introduced through Flyway migrations.

```text
Track Domain
     ↓
Persistence Model
     ↓
PostgreSQL
```

The persistence model may differ from the domain model when necessary.

---

# 4. Backend Implementation

## 4.1 Track Foundation

The first backend step is to establish the Track Module.

Tasks:

* Create the `track` module.
* Create the required Clean Architecture layers.
* Define the Track domain model.
* Define the required repository abstractions.
* Define the initial Track use cases.

Initial use cases:

```text
Upload Track
Get Track
Stream Track
```

Delete functionality may be added if required by the Phase 1 implementation.

---

## 4.2 Track Persistence

The system needs to persist Track metadata.

Tasks:

* Design the Track database table.
* Create the initial Flyway migration.
* Implement the persistence model.
* Implement the persistence adapter.
* Implement Track retrieval.

The expected flow is:

```text
Track Application
      ↓
Track Repository
      ↓
Persistence Adapter
      ↓
PostgreSQL
```

---

## 4.3 Audio Storage

Audio files are stored outside PostgreSQL.

For Phase 1, the system will use local file storage.

```text
Phase 1
    ↓
Local File System
```

The storage implementation should be accessed through an abstraction so that the implementation can be replaced in a later phase.

For example:

```text
AudioStorage
     │
     └── LocalFileAudioStorage
```

A future implementation may use object storage such as MinIO or Amazon S3.

This change should not require major changes to the Track application logic.

---

## 4.4 Upload Track

The first complete backend vertical slice is the Upload Track flow.

### Request Flow

```text
Flutter / HTTP Client
        ↓
Track Controller
        ↓
Upload Track Use Case
        │
        ├──────────────→ Audio Storage
        │                    ↓
        │                 Audio File
        │
        └──────────────→ Track Repository
                             ↓
                         PostgreSQL
```

The upload operation should:

1. Receive the audio file and track metadata.
2. Validate the request.
3. Store the audio file.
4. Persist the track metadata.
5. Return the created track information.

The system should not store the raw audio binary directly in PostgreSQL.

---

## 4.5 Get Track

The system must provide an API for retrieving track information.

Conceptually:

```text
GET /api/v1/tracks/{id}
```

Request flow:

```text
Client
   ↓
Track Controller
   ↓
Get Track Use Case
   ↓
Track Repository
   ↓
PostgreSQL
```

The response should contain the information required by the Flutter application to display and play the track.

---

## 4.6 Audio Streaming

Audio streaming is the main technical focus of Phase 1.

The backend must support HTTP Range Requests.

A client may request a specific byte range:

```text
Range: bytes=100000-200000
```

The server should return the requested portion of the audio file instead of returning the entire file.

The expected response is:

```text
206 Partial Content
```

The streaming response should correctly handle relevant HTTP headers, including:

```text
Accept-Ranges
Content-Range
Content-Length
Content-Type
```

### Streaming Flow

```text
Flutter Audio Player
        │
        │ GET /api/v1/tracks/{id}/stream
        │ Range: bytes=x-y
        ▼
Track Controller
        ↓
Stream Track Use Case
        ↓
Audio Storage
        ↓
Requested Audio Bytes
        ↓
206 Partial Content
        ↓
Flutter Audio Player
```

Supporting HTTP Range Requests is required for playback seeking.

---

# 5. Flutter Implementation

## 5.1 Track API Integration

After the backend Track APIs are working, the Flutter application will integrate with them.

The Flutter application should be able to:

* Upload a track.
* Retrieve track information.
* Request the audio stream.

The initial Flutter structure will focus only on the features required by Phase 1.

```text
lib/
├── core/
└── features/
    ├── track/
    └── player/
```

---

## 5.2 Audio Player

The Flutter application will integrate an audio player capable of consuming the backend audio stream.

Basic playback functionality:

```text
Play
Pause
Resume
Stop
```

The player should use the Track streaming endpoint rather than downloading the entire audio file before playback.

---

## 5.3 Playback and Seeking

The audio player must support seeking.

Example:

```text
Current Position
      ↓
      ───────────────●──────────────
                     ↑
                   Seek
```

Seeking should cause the audio player to request the appropriate byte range from the backend.

This provides an end-to-end validation of the HTTP Range implementation.

---

# 6. Testing and Validation

## 6.1 Backend Tests

Each backend vertical slice should be tested before moving to the next one.

### Upload

Verify:

* The request is accepted.
* The audio file is stored.
* Track metadata is persisted.
* The correct Track ID is returned.

### Retrieval

Verify:

* An existing Track can be retrieved.
* Track metadata is returned correctly.
* A non-existing Track is handled correctly.

### Streaming

Verify:

* Range Requests are accepted.
* The server returns `206 Partial Content`.
* The requested byte range is correct.
* Required response headers are present.

---

## 6.2 Flutter Tests

Verify:

* Track information can be displayed.
* Audio playback starts successfully.
* Playback can be paused and resumed.
* Seeking works correctly.

---

## 6.3 End-to-End Test

The final test must validate the complete flow:

```text
                LaSono

Flutter
   │
   │ Upload Track
   ▼
Spring Boot
   │
   ├──────────────→ Local Storage
   │                     │
   │                  Audio File
   │
   └──────────────→ PostgreSQL
                         │
                      Metadata
                         │
                         ▼
Flutter ◄────────── Get Track
   │
   │ Play
   ▼
Audio Player
   │
   │ HTTP Range Request
   ▼
Spring Boot
   │
   ▼
Local Storage
   │
   │ Partial Audio Data
   ▼
Audio Player
   │
   ▼
Play + Seek
```

---

# 7. Implementation Order

The implementation should follow this order:

```text
1. Track Foundation
       ↓
2. Track Persistence
       ↓
3. Audio Storage
       ↓
4. Upload Track
       ↓
5. Get Track
       ↓
6. Audio Streaming
       ↓
7. Flutter Track Integration
       ↓
8. Flutter Audio Player
       ↓
9. Playback & Seeking
       ↓
10. End-to-End Validation
```

Each step should be implemented and tested before moving to the next step.

---

# 8. Phase Completion Criteria

Phase 1 is complete when the following flow works successfully:

```text
Upload
  ↓
Store Audio
  ↓
Store Metadata
  ↓
Retrieve Track
  ↓
Request Audio Stream
  ↓
HTTP Range
  ↓
Play Audio
  ↓
Seek Audio
```

The final result should demonstrate that LaSono can perform its first complete audio workflow from the Flutter client, through the Spring Boot backend, to persistent storage and back to the audio player.

---

## Out of Scope for Phase 1

The following features are intentionally excluded from Phase 1:

* Authentication
* User profiles
* Likes
* Comments
* Follows
* Playlists
* Feed
* Search
* Recommendations
* Redis
* Kafka
* Elasticsearch
* CDN
* Microservices
* Adaptive streaming
* Production object storage

These features can be introduced in later phases when the core audio system is stable.
