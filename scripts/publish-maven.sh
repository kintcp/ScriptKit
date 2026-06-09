#!/bin/bash

set -euo pipefail

# Configuration
ARTIFACT_ID="$1"
VERSION="$2"
AAR_PATH="$3"
GROUP_ID="org.xscript"

MAVEN_REPO_DIR="$(pwd)/maven-repo"
mkdir -p "$MAVEN_REPO_DIR"

# Convert dots to slashes for Group ID
GROUP_PATH=$(echo "$GROUP_ID" | tr '.' '/')
ARTIFACT_PATH=$(echo "$ARTIFACT_ID") # Artifact ID can have dots in Maven
VERSION_DIR="$MAVEN_REPO_DIR/$GROUP_PATH/$ARTIFACT_PATH/$VERSION"

mkdir -p "$VERSION_DIR"

# Copy AAR
cp "$AAR_PATH" "$VERSION_DIR/$ARTIFACT_ID-$VERSION.aar"

# Generate POM
cat > "$VERSION_DIR/$ARTIFACT_ID-$VERSION.pom" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<project xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd" xmlns="http://maven.apache.org/POM/4.0.0"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <modelVersion/4.0.0</modelVersion>
  <groupId>$GROUP_ID</groupId>
  <artifactId>$ARTIFACT_ID</artifactId>
  <version>$VERSION</version>
  <packaging>aar</packaging>
  <name>$ARTIFACT_ID</name>
  <description>Android AAR for $ARTIFACT_ID</description>
</project>
EOF

# Update Maven Metadata
METADATA_DIR="$MAVEN_REPO_DIR/$GROUP_PATH/$ARTIFACT_PATH"
METADATA_FILE="$METADATA_DIR/maven-metadata.xml"

if [ ! -f "$METADATA_FILE" ]; then
    cat > "$METADATA_FILE" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<metadata>
  <groupId>$GROUP_ID</groupId>
  <artifactId>$ARTIFACT_ID</artifactId>
  <versioning>
    <latest>$VERSION</latest>
    <release>$VERSION</release>
    <versions>
      <version>$VERSION</version>
    </versions>
    <lastUpdated>$(date +%Y%m%d%H%M%S)</lastUpdated>
  </versioning>
</metadata>
EOF
else
    # Simple version update logic (could be improved with proper XML parsing)
    if ! grep -q "<version>$VERSION</version>" "$METADATA_FILE"; then
        sed -i "s|<versions>|<versions>\n      <version>$VERSION</version>|" "$METADATA_FILE"
    fi
    sed -i "s|<latest>.*</latest>|<latest>$VERSION</latest>|" "$METADATA_FILE"
    sed -i "s|<release>.*</release>|<release>$VERSION</release>|" "$METADATA_FILE"
    sed -i "s|<lastUpdated>.*</lastUpdated>|<lastUpdated>$(date +%Y%m%d%H%M%S)</lastUpdated>|" "$METADATA_FILE"
fi

echo "Maven artifacts for $ARTIFACT_ID:$VERSION generated at $VERSION_DIR"
