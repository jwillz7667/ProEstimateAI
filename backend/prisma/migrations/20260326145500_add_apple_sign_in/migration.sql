-- AlterTable
ALTER TABLE "User" ADD COLUMN "appleUserId" TEXT;

-- Make passwordHash nullable for Apple-only users
ALTER TABLE "User" ALTER COLUMN "passwordHash" DROP NOT NULL;

-- CreateIndex
CREATE UNIQUE INDEX "User_appleUserId_key" ON "User"("appleUserId");
