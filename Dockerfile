FROM node:22-alpine AS builder
# libc6-compat might be needed for some dependencies
RUN apk add --no-cache libc6-compat

WORKDIR /app

# Install pnpm globally
RUN npm install -g pnpm

# Copy package files and install dependencies
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

# Copy all source files
COPY . .

ARG DATABASE_TYPE
ARG BASE_PATH

ENV DATABASE_TYPE=$DATABASE_TYPE
ENV BASE_PATH=$BASE_PATH
ENV NEXT_TELEMETRY_DISABLED=1

# Install npm-run-all since build-docker depends on it
RUN pnpm add npm-run-all

# Run build script
RUN pnpm run build-docker

# Final stage: production runtime
FROM node:22-alpine AS runner
WORKDIR /app

ARG NODE_OPTIONS

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_OPTIONS=$NODE_OPTIONS

# Add user and group for security
RUN addgroup --system --gid 1001 nodejs && \
    adduser --system --uid 1001 nextjs

RUN npm install -g pnpm
RUN apk add --no-cache curl

# Copy installed dependencies from builder (including npm-run-all)
COPY --from=builder --chown=nextjs:nodejs /app/node_modules ./node_modules
COPY --from=builder --chown=nextjs:nodejs /app/package.json ./package.json
COPY --from=builder --chown=nextjs:nodejs /app/pnpm-lock.yaml ./pnpm-lock.yaml

# Copy necessary built files from builder
COPY --from=builder --chown=nextjs:nodejs /app/public ./public
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/scripts ./scripts

COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static

RUN mv ./.next/routes-manifest.json ./.next/routes-manifest-orig.json

USER nextjs

EXPOSE 3000

ENV HOSTNAME=0.0.0.0
ENV PORT=3000

CMD ["pnpm", "start-docker"]
