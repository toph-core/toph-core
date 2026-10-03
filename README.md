# toph-core

toph-core builds point-of-sale systems, restaurant management software, Telegram bots and mini apps, backend services, and web tools.

The repositories listed below are private. Repository access is available by request.

## Products

Mary AI is a restaurant management and point-of-sale platform consisting of five repositories: a Windows POS client, a management web dashboard, a central API backend, a face recognition app for staff attendance, and a data migration tool.

### [Mary-Ai-POS](https://github.com/toph-core/Mary-Ai-POS)

A desktop point-of-sale application for restaurants, built for cashier and waitstaff operations.

- Runs local-first using an embedded SQLite database so order entry, table billing, and receipts function without an internet connection.
- Prints customer bills and kitchen tickets over ESC/POS thermal printers via TCP/IP and Windows USB.
- Coordinates multiple terminal nodes on a local area network using leader election and resource leases.
- Manages table maps, order courses, split payments, waiter assignments, and cash register shifts.
- Status: Core cashier and offline ordering are implemented; peer-to-peer local network replication is in progress.
- Stack: Flutter (Dart), SQLite (`sqlite3`), Windows native APIs (`win32`, FFI).

### [MaryAiFront](https://github.com/toph-core/MaryAiFront)

A web-based administration dashboard for restaurant back-office operations.

- Manages menus, categories, ingredients, composite recipes, item modifiers, and stop lists.
- Provides an interactive canvas editor to build and arrange restaurant floor plans and table layouts.
- Tracks warehouse stock levels, internal transfers, supplier shipments, write-offs, and cash registers.
- Displays sales reports, hourly turnover statistics, staff schedules, and shift logs across branches.
- Stack: React 19, TypeScript, Vite, Material UI (MUI), Redux Toolkit, Konva (`react-konva`), SWR.

### [mary-ai-backend](https://github.com/toph-core/mary-ai-backend)

A REST API backend and sync engine powering the Mary AI restaurant platform.

- Serves REST endpoints for orders, table sessions, payments, inventory deductions, and staff permissions.
- Supplies data snapshots and change logs so offline POS terminals can sync when they reconnect.
- Integrates digital payment gateways alongside physical cash, card, and split payment processing.
- Handles multi-language responses in English, Russian, and Uzbek, with automated OpenAPI documentation.
- Stack: Go (Echo framework), PostgreSQL (`pgx`, `lib/pq`), Redis, MinIO, Docker.

### [face-id-app](https://github.com/toph-core/face-id-app)

A desktop biometric application for employee verification and attendance tracking.

- Captures camera frames on a background thread to prevent UI freezing.
- Detects faces with the YuNet ONNX neural network, with fallback support for OpenCV cascades and dlib HOG.
- Computes 128-dimensional facial embeddings to identify registered employees from a local photo database.
- Displays visual bounding boxes and identification status with adjustable match thresholds and frame downscaling.
- Stack: Python 3, PyQt6, OpenCV, YuNet ONNX, `face_recognition` (dlib), NumPy.

### [neon-alisa-scraper](https://github.com/toph-core/neon-alisa-scraper)

A migration tool that moves a restaurant's existing data into Mary AI when it switches from another system.

- Reads branches, menus, recipes, warehouses and order history from the previous system.
- Maps each record onto the Mary AI data model and ID format.
- Imports the result through the backend API and reports what synced and what did not.
- Stack: Go.

## Projects

### [telegram-bots](https://github.com/toph-core/telegram-bots)

A monorepo containing a reusable Telegram bot framework and commercial bot services.

- Includes `tgkit`, a bot framework providing user registration, role hierarchies, multi-language strings (English, Russian, Uzbek Latin, Uzbek Cyrillic), multi-step conversational flows, and Telegram Stars payments.
- Includes `paid-channel`, a subscription gate that admits paying members to private channels and removes them when subscriptions lapse.
- Includes `navbat`, a multi-tenant booking platform for service businesses, with double-booking prevented by a database constraint (in progress).
- Includes `hub`, a storefront bot with an AI concierge powered by the Gemini API for product inquiries and instant checkout.
- Stack: Python 3, aiogram 3, SQLite, PostgreSQL, Redis, Telethon (MTProto), Google Gemini API.

### [chess](https://github.com/toph-core/chess)

A Telegram Game and Mini App for playing chess and checkers against computer engines or human opponents.

- Plays chess against the Stockfish engine and Russian draughts against a custom Go rules engine.
- Supports in-chat interactive duels on an 8x8 grid of Telegram inline buttons without opening a browser.
- Includes 12 character opponents with distinct opening preferences, chat lines, and dynamic Elo ratings.
- Delivers a touch-friendly Telegram Mini App interface with lobby matchmaking and leaderboards.
- Stack: Go, Stockfish, Telegram Bot API, HTML5, JavaScript, CSS.

### [jobhunt](https://github.com/toph-core/jobhunt)

A job search automation tool that aggregates listings, tracks applications, and coordinates outreach.

- Collects job postings from job boards and Telegram channels using a direct MTProto client.
- Keeps every job on a board by status, with analytics on what was found and sent.
- Generates application messages from templates and dispatches them via email or direct Telegram messages.
- Connects with Google Calendar via OAuth to schedule and track interviews.
- Stack: Go, SQLite, `gotd/td` (MTProto), `goquery`, Google Calendar API.

### [api](https://github.com/toph-core/api)

A FastAPI backend starter providing authentication and user administration.

- Implements password hashing with Argon2id and rotating refresh tokens stored as hashes to prevent replay.
- Enforces role-based permissions across standard user, developer, administrator, and owner roles.
- Supports PostgreSQL, MySQL, and SQLite through connection URL strings, with secondary read-only database connections.
- Provides admin endpoints for searching, filtering, and paginating user accounts, accompanied by automated tests.
- Stack: Python 3, FastAPI, SQLAlchemy (async), Alembic, Pydantic, pytest.

### [fastapi](https://github.com/toph-core/fastapi)

A modular backend repository with microservice isolation and inter-service gRPC communication.

- Manages microservices and shared libraries within a single repository using `uv` workspaces.
- Connects internal services via gRPC alongside public-facing FastAPI HTTP endpoints.
- Includes `apa`, a developer command-line tool for service management, migrations, protobuf generation, and testing.
- Packages services in Docker with Nginx reverse proxy routing and GitHub Actions CI/CD workflows.
- Stack: Python 3, FastAPI, gRPC (`grpcio`, protobuf), PostgreSQL, SQLAlchemy (async), Alembic, Nginx, Docker.

### [extension](https://github.com/toph-core/extension)

A CRM integration widget for detecting and merging duplicate contact and deal records.

- Ingests incoming CRM webhooks with SHA-256 deduplication and Redis cooldown locks to prevent recursive update loops.
- Processes background duplicate scanning and merging tasks asynchronously using BullMQ.
- Merges duplicate contacts by combining field values, re-linking attached deals, and archiving redundant profiles.
- Provides an embedded settings and merge preview interface inside the CRM.
- Stack: TypeScript, Fastify, Prisma, PostgreSQL, Redis, BullMQ, React, Vite, Tailwind CSS.

### [referral-bot](https://github.com/toph-core/referral-bot)

A Telegram bot for tracking member acquisition and referral campaigns.

- Verifies required channel membership before allowing users to interact with bot features.
- Generates deep-linked invite parameters to credit incoming users to their referrers.
- Maintains user referral counts and provides real-time ranking leaderboards.
- Stack: Python 3, aiogram 3, SQLite (`aiosqlite`), Docker.

### [test-chat-app](https://github.com/toph-core/test-chat-app)

A real-time chat application demonstrating WebSocket distribution across scalable server instances.

- Manages bi-directional WebSocket chat connections with message persistence in PostgreSQL.
- Broadcasts chat messages across application nodes using a RabbitMQ fanout exchange.
- Serves a single-page chat user interface built with React and Vite behind an Nginx reverse proxy.
- Stack: Python 3, FastAPI, WebSockets, RabbitMQ (`aio-pika`), PostgreSQL (SQLAlchemy async), React, Vite, TypeScript.

### [portfolio](https://github.com/toph-core/portfolio)

A personal portfolio website built without build tools or third-party runtime dependencies.

- A personal site in semantic HTML5 and plain CSS, with a set of design explorations alongside it.
- Operates without build steps, bundlers, or package managers.
- Includes Open Graph preview metadata and static hosting configuration for GitHub Pages.
- Stack: HTML5, CSS3, JavaScript.

## Stack at a glance

| Repository | Domain | Primary language | Key technologies |
|---|---|---|---|
| [Mary-Ai-POS](https://github.com/toph-core/Mary-Ai-POS) | Point of sale | Dart | Flutter, SQLite, Windows FFI, ESC/POS |
| [MaryAiFront](https://github.com/toph-core/MaryAiFront) | Back-office management | TypeScript | React 19, Vite, MUI, Redux Toolkit, Konva |
| [mary-ai-backend](https://github.com/toph-core/mary-ai-backend) | Platform API & sync engine | Go | Echo, PostgreSQL, Redis, MinIO, Docker |
| [face-id-app](https://github.com/toph-core/face-id-app) | Biometric attendance & auth | Python | PyQt6, OpenCV, YuNet ONNX, face_recognition |
| [neon-alisa-scraper](https://github.com/toph-core/neon-alisa-scraper) | Legacy data migration | Go | Go standard library, HTTP client |
| [telegram-bots](https://github.com/toph-core/telegram-bots) | Bot framework & services | Python | aiogram 3, SQLite, PostgreSQL, Redis, Telethon, Gemini API |
| [chess](https://github.com/toph-core/chess) | Games & Mini Apps | Go | Stockfish, Telegram Bot API, HTML5 Canvas |
| [jobhunt](https://github.com/toph-core/jobhunt) | Job search & application CRM | Go | SQLite, gotd/td (MTProto), goquery, Google API |
| [api](https://github.com/toph-core/api) | Auth & user management starter | Python | FastAPI, SQLAlchemy, Alembic, Argon2id |
| [fastapi](https://github.com/toph-core/fastapi) | Microservice monorepo | Python | FastAPI, gRPC, PostgreSQL, Alembic, Nginx |
| [extension](https://github.com/toph-core/extension) | CRM duplicate merger widget | TypeScript | Fastify, Prisma, PostgreSQL, Redis, BullMQ, React |
| [referral-bot](https://github.com/toph-core/referral-bot) | Telegram referral tracker | Python | aiogram 3, SQLite, Docker |
| [test-chat-app](https://github.com/toph-core/test-chat-app) | Distributed real-time chat | Python / TypeScript | FastAPI, WebSockets, RabbitMQ, PostgreSQL, React |
| [portfolio](https://github.com/toph-core/portfolio) | Static personal site | HTML / CSS | Semantic HTML5, CSS3, GitHub Pages |
