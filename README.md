<img width="3712" height="1152" alt="banner (2)" src="https://github.com/user-attachments/assets/ef6c7792-072e-4b9a-b3be-38cb18df8f2a" />

# RaceDay – Event Management System (Part 3)

RaceDay is a full-stack event management platform for the South African road running, walking and cycling community.
**Organisers** create events, manage categories, track enrolments and publish results.
**Participants** browse upcoming events, enter a category, follow their entry status and track their personal results.

Part 3 adds an **ASP.NET Core MVC web application** that consumes the Part 2 RESTful API, **Blob Storage with Azurite**
(the Azure Storage emulator) for event banners and profile pictures, and **Docker** containerisation of the MVC application.

---

## Contents

1. [Video presentation](#video-presentation)
2. [Architecture](#architecture)
3. [Repository structure](#repository-structure)
4. [Features](#features)
5. [User interface](#user-interface)
6. [Prerequisites](#prerequisites)
7. [Setup – database](#1-database)
8. [Setup – Blob Storage (Azurite)](#2-blob-storage-azurite)
9. [Demo data and logins](#3-demo-data-and-logins)
10. [Running the API](#4-run-the-api)
11. [Running the MVC app locally](#5-run-the-mvc-app-locally)
12. [Running the MVC app in Docker](#6-run-the-mvc-app-in-docker)
13. [Testing](#testing)
14. [CI/CD](#cicd)
15. [Part 3 changes to the API](#part-3-changes-to-the-part-2-api)
16. [References](#references)

---

## Video presentation

**YouTube (unlisted):** [https://youtu.be/REPLACE_WITH_YOUR_PART3_VIDEO_ID](https://youtu.be/qpuFORige5Y)

Part 2 video: https://youtu.be/EyEZxugOiTE

---

## Architecture

```text
 Browser ──HTTP──► RaceDay_MVC (ASP.NET Core MVC, Docker container :8080)
                       │  typed HttpClient (RaceDayApiClient)
                       │  forwards the user's API session cookie
                       ▼
                   RaceDay_API (ASP.NET Core Web API :5027)
                       │                    │
                 EF Core│                    │ Azure.Storage.Blobs
                       ▼                    ▼
              SQL Server (RaceDayDB)   Azurite Blob Storage (container: raceday-images)
```

* The MVC project has **no database access and no business rules**. Every read and write goes through the API.
* The MVC project **never talks to Blob Storage**. Image files are posted to the API, which uploads them to Azurite
  and saves the returned URL in the database. The browser then displays the image from that URL.
* Role-based access is enforced in the API (`[Authorize(Roles = ...)]`) **and** reflected in the MVC app
  (`[RequireRole(...)]` filter + a different navigation menu per role).

---

## Repository structure

```text
.
├── .github/workflows/
│   ├── ci.yml                      # Structure check → build + test (API & MVC) → Docker build + smoke test
│   └── autograde.yaml
├── Database/
│   ├── RaceDay_Part3_SchemaChanges.sql   # Part 3 columns and event type constraint
│   ├── RaceDay_Demo_Data.sql             # Demo organisers, participants, events, entries and results
│   └── RaceDay_Demo_Data_Remove.sql      # Removes the demo data
├── RaceDay_API/                    # Part 2 Web API (extended for Part 3)
│   ├── RaceDay_API/
│   │   ├── Controllers/            # Auth, Events, Categories, Enrolments, Results, Profile,
│   │   │                           # EventBanner (new), ProfilePicture (new), Routes, Weather, Roles
│   │   ├── Services/               # SessionAuthenticationHandler, BlobStorageService (new), DatabaseSchemaUpdater (new)
│   │   ├── Models/  Data/  Data Transfer Objects/
│   │   └── Program.cs
│   └── RaceDay_API.Tests/          # xUnit tests (Part 2 + Part 3)
├── RaceDay_MVC/                    # Part 3 MVC web application
│   ├── Controllers/                # Account, Home, Dashboard, ManageEvents, Categories, Enrolments,
│   │                               # Results, Events, MyEnrolments, MyResults, Profile
│   ├── Services/RaceDayApiClient.cs  # The only way the MVC app gets data
│   ├── Infrastructure/             # Session helpers, RequireRole filter, error filter, UI helpers
│   ├── Models/Api/                 # Shapes of the API's JSON responses
│   ├── Models/ViewModels/          # Form and page models with validation
│   ├── Views/                      # Razor views (Bootstrap 5, RaceDay theme)
│   └── wwwroot/                    # site.css, site.js, images, Bootstrap, jQuery validation
├── RaceDay_MVC.Tests/              # xUnit tests for the MVC app
├── Dockerfile                      # Multi-stage build of the MVC app
├── .dockerignore
├── docker-compose.yml              # Azurite + MVC app
└── RaceDay.slnx                    # Solution containing all four projects
```

---

## Features

### Authentication and role-based navigation
* Register (choose **Organiser** or **Participant**) and log in through the API (passwords hashed with BCrypt by the API).
* The logged-in user's id, name, role and API session cookie are stored in the **MVC session** and used on every page.
* Each role has its own navigation menu and home page (Organiser → Dashboard, Participant → Events).
* Protected pages redirect anonymous users to **Log in** (and back again afterwards); the wrong role sees **Access denied**.
* **Log out** ends the API session and the MVC session; protected pages are sent with `Cache-Control: no-store`
  so they cannot be reopened with the Back button.
* If the API session expires, the user is redirected to log in with a friendly message.

### Organiser interface
| Page | What it does |
|---|---|
| **Dashboard** | Totals (events, upcoming, open, enrolments), upcoming event dates, table of enrolments per event |
| **My Events** | Event cards with counts and quick links |
| **Create / Edit event** | Name, description, date, location, distance, event type, status and **banner image upload** |
| **Delete event** | Confirmation page; deletes the event and its categories, enrolments and results |
| **Categories** | Add, edit and delete age or distance categories (name, distance, fee, start time) |
| **Enrolments** | Every participant entered in the event, their category, bib and colour-coded status; change status |
| **Results** | Capture/correct finish time, position and status (Finished, DNF, DNS, DSQ) after the event, then **publish** (event → Completed) |

### Participant interface
| Page | What it does |
|---|---|
| **Events (home)** | Upcoming events with filters: search, event type, date range, open for entries only |
| **Event details** | Banner, full information, categories, routes, weather and **Enter event** (choose a category) |
| **My Entries** | Upcoming and past entries with colour-coded status (green Confirmed, amber Pending, red Cancelled, grey Refunded); withdraw |
| **My Results** | Personal race history: event, date, category, finish time and position, e.g. *47th out of 312 finishers* |
| **Profile** | View/update personal details and password, upload a **profile picture** |

### Error handling
* Client-side and server-side validation on every form.
* API error messages are translated into friendly sentences; raw exceptions are never shown.
* Branded pages for 404, unexpected errors and "API unavailable".

---

## User interface

### Landing page
<img width="1542" height="949" alt="Landing page" src="https://github.com/user-attachments/assets/183369e5-316d-442e-97f3-d0e56cf30194" />

### Login screen
<img width="1409" height="940" alt="Login screen" src="https://github.com/user-attachments/assets/03a0a9d5-594e-418d-828d-2596e8fc4c3a" />

### Organiser dashboard
<img width="1896" height="984" alt="Organiser dashboard" src="https://github.com/user-attachments/assets/355d0910-d1ef-4556-8e6f-6c29dc69a5ca" />

### Participant dashboard
<img width="1355" height="948" alt="image" src="https://github.com/user-attachments/assets/c48f21c3-0fea-495f-831f-f25d0e5f8afd" />


---

## Prerequisites

* [.NET 10 SDK](https://dotnet.microsoft.com/download)
* SQL Server (Express is fine) with the **RaceDayDB** database from Part 1
* [Docker Desktop](https://www.docker.com/products/docker-desktop/) (runs Azurite and the MVC container)
* Visual Studio 2022/2026 or VS Code

---

## 1. Database

1. Make sure `RaceDayDB` exists (Part 1 script).
2. Open `Database/RaceDay_Part3_SchemaChanges.sql` in SQL Server Management Studio and click **Execute**.
   It adds the three Part 3 columns and allows the event types `Running`, `Walking` and `Cycling`.
   It is safe to run more than once, and the API applies the same changes when it starts.
3. Update the `RaceDayConnection` connection string in `RaceDay_API/RaceDay_API/appsettings.json` if your server name is different.

## 2. Blob Storage (Azurite)

Images are stored in **Azurite**, the Azure Blob Storage emulator, using the `Azure.Storage.Blobs` SDK.

1. Start Docker Desktop, then start Azurite from the repository root:

```bash
docker compose up -d azurite
```

2. The API connects with `"AzureBlobStorage:ConnectionString": "UseDevelopmentStorage=true"` in `appsettings.json`
   (Azurite on `http://127.0.0.1:10000`).
3. The API creates the `raceday-images` container on the first upload.

## 3. Demo data and logins

Run `Database/RaceDay_Demo_Data.sql` in SQL Server Management Studio to add demo events, entries and results.
Every demo account uses the password **RaceDay@2026**.

| Role | Email |
|---|---|
| Organiser | mitchelle@gmail.com |
| Participant (has entries and results) | teressa@gmail.com |

## 4. Run the API

```bash
cd RaceDay_API/RaceDay_API
dotnet run --launch-profile http
```

The API listens on **http://localhost:5027** (Swagger: http://localhost:5027/swagger).

## 5. Run the MVC app locally

```bash
cd RaceDay_MVC
dotnet run --launch-profile http
```

Open **http://localhost:5066**. The API address is set in `RaceDay_MVC/appsettings.json` → `ApiSettings:BaseUrl`.

## 6. Run the MVC app in Docker

Start the API first (step 4). Then, from the repository root, **one command builds and starts Azurite and the MVC container**:

```bash
docker compose up --build -d
```

Or with plain Docker:

```bash
docker build -t raceday-mvc .
docker run -d -p 8080:8080 --name raceday-mvc -e ApiSettings__BaseUrl=http://host.docker.internal:5027 raceday-mvc
```

Open **http://localhost:8080**. The container reaches the API on your machine through `host.docker.internal`.

Stop everything with `docker compose down`.

If the container cannot reach the API, run the API with `dotnet run --launch-profile http-docker`.

**Dockerfile best practices used:** multi-stage build (SDK image to build, small ASP.NET runtime image to run),
restore layer cached separately from the source, `.dockerignore` to keep the build context small,
`UseAppHost=false`, configuration through environment variables, and the container runs as the **non-root** `app` user.

---

## Testing

```bash
dotnet test RaceDay.slnx
```

* **RaceDay_API.Tests**: 63 tests (Part 2 tests plus Part 3 tests for banner/profile uploads, event validation,
  filtering, dashboard, publishing results and "47th of 312" finisher totals).
* **RaceDay_MVC.Tests**: 28 tests (role filter redirects, API cookie forwarding, API error translation, UI helpers).

---

## CI/CD

`.github/workflows/ci.yml` runs on every push and pull request:

1. **Validate repository structure:** required files exist, the MVC project has no database or Blob Storage references,
   and the README contains the Docker command and video link.
2. **Build and test:** restores, builds (API + MVC) and runs all tests on .NET 10.
3. **Docker:** builds the image, starts the container and checks that it serves pages.

**Successful build:**

![Green CI build](docs/ci-green-build.png)

---

## Part 3 changes to the Part 2 API

| Change | Why |
|---|---|
| `POST/DELETE api/events/{id}/banner` | Organiser uploads an event banner → Blob Storage (Azurite) → URL saved on the event |
| `POST/DELETE api/profile/picture` | Profile picture upload → Blob Storage (Azurite) → URL saved on the user |
| `GET api/events/mine` | Organiser dashboard (category, enrolment and result counts) |
| `PUT api/events/{id}/status` | Publish results (mark an event Completed) |
| `GET api/events` filters | `search`, `eventType`, `fromDate`, `toDate`, `upcomingOnly`, `openOnly`; participants never see Draft events |
| Event `distance`, category `startTime` | Required fields for the event and category pages |
| Validation | Event type/status/name/location/distance, duplicate events, results only after the event date |
| Richer responses | My enrolments, my results (with total finishers), event enrolments (with results) |
| Event type constraint | `Running`, `Walking` and `Cycling` are accepted by the database |
| HTTPS redirect only outside Development | The MVC container calls the API over HTTP on port 5027 |

---

## References

Microsoft (2025) *Use the Azurite emulator for local Azure Storage development*. Available at: https://learn.microsoft.com/en-us/azure/storage/common/storage-use-azurite (Accessed: 20 November 2026).

Microsoft (2025) *Quickstart: Azure Blob Storage client library for .NET*. Available at: https://learn.microsoft.com/en-us/azure/storage/blobs/storage-quickstart-blobs-dotnet (Accessed: 18 November 2026).

Microsoft (2025) *Make HTTP requests using IHttpClientFactory in ASP.NET Core*. Available at: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/http-requests (Accessed: 18 November 2026).

Microsoft (2025) *Session and state management in ASP.NET Core*. Available at: https://learn.microsoft.com/en-us/aspnet/core/fundamentals/app-state (Accessed: 18 November 2026).

Microsoft (2025) *Containerize a .NET app*. Available at: https://learn.microsoft.com/en-us/dotnet/core/docker/build-container (Accessed: 18 November 2026).

Docker (2025) *Multi-stage builds*. Available at: https://docs.docker.com/build/building/multi-stage/ (Accessed: 18 November 2026).

Bootstrap (2025) *Bootstrap 5 documentation*. Available at: https://getbootstrap.com/docs/5.3/ (Accessed: 18 November 2026).

Microsoft (n.d.) *Integration tests in ASP.NET Core*. Available at: https://learn.microsoft.com/en-us/aspnet/core/test/integration-testing (Accessed: 18 October 2026).

Figma (2026) Figma [Design software]. Available at: https://www.figma.com (Accessed: 20 November 2026).
