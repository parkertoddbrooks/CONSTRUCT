#!/bin/bash

# Enhanced Context Updater for CLAUDE.md
# Includes sprint context, decisions, patterns, and metrics

# Source project detection library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../lib/project-detection.sh"

# Get project paths
PROJECT_ROOT="$(get_project_root)"
PROJECT_NAME="$(get_project_name)"
XCODE_DIR="$(get_xcode_project_dir)"
IOS_DIR="$(get_ios_app_dir)"
WATCH_DIR="$(get_watch_app_dir)"
CONTEXT_FILE="$PROJECT_ROOT/CLAUDE.md"
TEMP_DIR=$(mktemp -d)

# Backup before updating
# Create trash directory with date
TRASH_DIR="$PROJECT_ROOT/_trash/$(date +%Y-%m-%d)"
mkdir -p "$TRASH_DIR"
# Move backup to trash
cp "$CONTEXT_FILE" "$TRASH_DIR/CLAUDE.md.backup-$(date +%H%M%S)"

# Generate sections in separate files
generate_structure() {
    cat > "$TEMP_DIR/structure.txt" <<'EOF'
## 📊 Current Project State (Auto-Updated)
EOF
    echo "Last updated: $(date '+%Y-%m-%d %H:%M:%S')" >> "$TEMP_DIR/structure.txt"
    
    # Count components
    local viewmodels=$(find "$XCODE_DIR" -name "*ViewModel*.swift" -type f | grep -v "build/" | wc -l | tr -d ' ')
    local services=$(find "$XCODE_DIR" -name "*Service*.swift" -type f | grep -v "build/" | wc -l | tr -d ' ')
    local tokens=$(find "$XCODE_DIR" -name "*Tokens*.swift" -type f | grep -v "build/" | wc -l | tr -d ' ')
    local components=$(find "$IOS_DIR/Shared/Components" -name "*.swift" -type f 2>/dev/null | wc -l | tr -d ' ')
    
    cat >> "$TEMP_DIR/structure.txt" <<EOF

### Active Components
- ViewModels: $viewmodels
- Services: $services  
- Design Tokens: $tokens
- Shared Components: $components

### Available Resources

#### 🎨 Design System
EOF
    
    # Check design system files
    if [ -f "$IOS_DIR/Core/DesignSystem/Colors.swift" ]; then
        echo "- ✅ AppColors available" >> "$TEMP_DIR/structure.txt"
    fi
    if [ -f "$IOS_DIR/Core/DesignSystem/Spacing.swift" ]; then
        echo "- ✅ Spacing.small/medium/large" >> "$TEMP_DIR/structure.txt"
    fi
    if [ -f "$IOS_DIR/Core/DesignSystem/Typography.swift" ]; then
        echo "- ✅ Font system available" >> "$TEMP_DIR/structure.txt"
    fi
    
    echo "" >> "$TEMP_DIR/structure.txt"
    echo "#### 🧩 Shared Components" >> "$TEMP_DIR/structure.txt"
    find "$IOS_DIR/Shared/Components" -name "*.swift" -type f 2>/dev/null | while read -r file; do
        echo "- $(basename "$file" .swift)" >> "$TEMP_DIR/structure.txt"
    done | sort
}

generate_violations() {
    cat > "$TEMP_DIR/violations.txt" <<'EOF'
## ⚠️ Active Violations (Auto-Updated)

EOF
    
    # Check for hardcoded values
    echo "### Hardcoded Values" >> "$TEMP_DIR/violations.txt"
    if grep -r "CGFloat.*= [0-9]\|\.frame.*[0-9]" "$XCODE_DIR" --include="*.swift" 2>/dev/null | grep -v "Tokens\|tokens" | head -3 > "$TEMP_DIR/hardcoded.txt"; then
        if [ -s "$TEMP_DIR/hardcoded.txt" ]; then
            cat "$TEMP_DIR/hardcoded.txt" >> "$TEMP_DIR/violations.txt"
        else
            echo "✅ None found" >> "$TEMP_DIR/violations.txt"
        fi
    else
        echo "✅ None found" >> "$TEMP_DIR/violations.txt"
    fi
}

generate_location() {
    cat > "$TEMP_DIR/location.txt" <<'EOF'
## 📍 Current Working Location (Auto-Updated)

### Recently Modified Files
EOF
    
    find "$XCODE_DIR" -name "*.swift" -type f -mtime -1 2>/dev/null | grep -v "build/" | head -5 | while read -r file; do
        echo "- ${file#$PROJECT_ROOT/}" >> "$TEMP_DIR/location.txt"
    done
    
    echo "" >> "$TEMP_DIR/location.txt"
    echo "### Git Status" >> "$TEMP_DIR/location.txt"
    echo '```' >> "$TEMP_DIR/location.txt"
    cd "$PROJECT_ROOT" && git status --short | head -5 >> "$TEMP_DIR/location.txt"
    echo '```' >> "$TEMP_DIR/location.txt"
}

# Replace sections using perl (more reliable than awk for multiline)
replace_section() {
    local start_marker="$1"
    local end_marker="$2"
    local content_file="$3"
    
    perl -i -pe "
        if (/\Q$start_marker\E/../\Q$end_marker\E/) {
            if (/\Q$start_marker\E/) {
                print;
                open(FH, '<', '$content_file');
                while(<FH>) { print }
                close(FH);
            }
            \$_ = '' unless /\Q$end_marker\E/;
        }
    " "$CONTEXT_FILE"
}

# NEW: Generate Sprint Context
generate_sprint_context() {
    cat > "$TEMP_DIR/sprint-context.txt" <<'EOF'
## 🎯 Current Sprint Context (Auto-Updated)
EOF
    
    echo "**Date**: $(date '+%Y-%m-%d')" >> "$TEMP_DIR/sprint-context.txt"
    echo "**Time**: $(date '+%H:%M:%S')" >> "$TEMP_DIR/sprint-context.txt"
    
    # Git information
    cd "$PROJECT_ROOT"
    echo "**Branch**: $(git branch --show-current 2>/dev/null || echo 'main')" >> "$TEMP_DIR/sprint-context.txt"
    
    # Last commit
    local last_commit=$(git log -1 --pretty=format:"%h - %s" 2>/dev/null || echo "No commits")
    echo "**Last Commit**: $last_commit" >> "$TEMP_DIR/sprint-context.txt"
    
    # Current focus from recent changes
    echo "" >> "$TEMP_DIR/sprint-context.txt"
    echo "### Current Focus (from recent changes)" >> "$TEMP_DIR/sprint-context.txt"
    local recent_dirs=$(find "$XCODE_DIR" -name "*.swift" -type f -mtime -1 2>/dev/null | xargs -I {} dirname {} | sort | uniq | head -3)
    if [ -n "$recent_dirs" ]; then
        echo "$recent_dirs" | while read -r dir; do
            echo "- Working in: ${dir#$PROJECT_ROOT/}"
        done >> "$TEMP_DIR/sprint-context.txt"
    else
        echo "- No recent Swift file changes" >> "$TEMP_DIR/sprint-context.txt"
    fi
}

# NEW: Generate Recent Decisions
generate_recent_decisions() {
    cat > "$TEMP_DIR/decisions.txt" <<'EOF'
## 📋 Recent Architectural Decisions (Auto-Updated)

EOF
    
    # Look for DECISION: in recent commits
    cd "$PROJECT_ROOT"
    echo "### From Commit Messages" >> "$TEMP_DIR/decisions.txt"
    git log --grep="DECISION:" --pretty=format:"- %s" -10 2>/dev/null >> "$TEMP_DIR/decisions.txt" || echo "- No DECISION: tags found in commits" >> "$TEMP_DIR/decisions.txt"
    
    # Look for Decision: in dev logs
    echo "" >> "$TEMP_DIR/decisions.txt"
    echo "### From Dev Logs" >> "$TEMP_DIR/decisions.txt"
    if [ -d "$PROJECT_ROOT/AI/dev-logs" ]; then
        grep -h "Decision:" "$PROJECT_ROOT/AI/dev-logs"/*.md 2>/dev/null | head -5 | sed 's/.*Decision: /- /' >> "$TEMP_DIR/decisions.txt" || echo "- No decisions found in dev logs" >> "$TEMP_DIR/decisions.txt"
    fi
}

# NEW: Generate Pattern Library
generate_pattern_library() {
    cat > "$TEMP_DIR/patterns.txt" <<'EOF'
## 📚 Active Patterns (Auto-Generated)

EOF
    
    # Common ViewModel patterns
    echo "### Common @Published Properties" >> "$TEMP_DIR/patterns.txt"
    echo '```swift' >> "$TEMP_DIR/patterns.txt"
    grep -h "@Published" "$XCODE_DIR"/**/*ViewModel*.swift 2>/dev/null | sed 's/^[[:space:]]*//' | sort | uniq -c | sort -nr | head -5 >> "$TEMP_DIR/patterns.txt"
    echo '```' >> "$TEMP_DIR/patterns.txt"
}

# NEW: Generate Active PRDs Section
generate_active_prds() {
    cat > "$TEMP_DIR/prds.txt" <<'EOF'
## 📋 Active Product Requirements (Auto-Updated)

EOF
    
    # Current Sprint PRD
    echo "### Current Sprint" >> "$TEMP_DIR/prds.txt"
    if [ -f "$PROJECT_ROOT/AI/PRDs/current-sprint/"*.md ]; then
        for prd in "$PROJECT_ROOT/AI/PRDs/current-sprint/"*.md; do
            if [ -f "$prd" ]; then
                local prd_name=$(basename "$prd")
                echo "**Active PRD**: $prd_name" >> "$TEMP_DIR/prds.txt"
                echo "**Location**: AI/PRDs/current-sprint/$prd_name" >> "$TEMP_DIR/prds.txt"
                
                # Extract key goals from PRD (look for "Goals" or "Requirements" section)
                echo "" >> "$TEMP_DIR/prds.txt"
                echo "**Key Goals**:" >> "$TEMP_DIR/prds.txt"
                grep -A 5 -E "^##.*Goals|^##.*Requirements|^##.*Success Criteria" "$prd" 2>/dev/null | grep "^-" | head -5 >> "$TEMP_DIR/prds.txt" || echo "- See PRD for details" >> "$TEMP_DIR/prds.txt"
            fi
        done
    else
        echo "- No active sprint PRD found" >> "$TEMP_DIR/prds.txt"
    fi
    
    # Full App Vision
    echo "" >> "$TEMP_DIR/prds.txt"
    echo "### North Star Vision" >> "$TEMP_DIR/prds.txt"
    if [ -f "$PROJECT_ROOT/AI/PRDs/full-app/"*.md ]; then
        local vision_prd=$(ls -t "$PROJECT_ROOT/AI/PRDs/full-app/"*.md 2>/dev/null | grep -v "_ai-ignore" | head -1)
        if [ -f "$vision_prd" ]; then
            echo "**Document**: AI/PRDs/full-app/$(basename "$vision_prd")" >> "$TEMP_DIR/prds.txt"
            # Extract vision statement
            grep -m 1 -A 2 "Vision\|vision" "$vision_prd" 2>/dev/null | head -3 >> "$TEMP_DIR/prds.txt" || echo "- Professional DAW-quality running experience" >> "$TEMP_DIR/prds.txt"
        fi
    fi
    
    # Upcoming Features
    echo "" >> "$TEMP_DIR/prds.txt"
    echo "### Upcoming Features" >> "$TEMP_DIR/prds.txt"
    if [ -d "$PROJECT_ROOT/AI/PRDs/future" ]; then
        find "$PROJECT_ROOT/AI/PRDs/future" -name "*.md" -type f 2>/dev/null | grep -v "_ai-ignore" | head -5 | while read -r future_prd; do
            local feature_name=$(basename "$future_prd" .md | sed 's/_/ /g' | sed 's/-/ /g')
            echo "- $feature_name" >> "$TEMP_DIR/prds.txt"
        done || echo "- No future PRDs found" >> "$TEMP_DIR/prds.txt"
    fi
}

# Check if new sections exist, if not add them
add_new_sections_if_missing() {
    if ! grep -q "<!-- START:SPRINT-CONTEXT -->" "$CONTEXT_FILE"; then
        echo "Adding new automation sections to CLAUDE.md..."
        # Add after the CURRENT-STRUCTURE section
        perl -i -pe 's/(<!-- END:CURRENT-STRUCTURE -->)/$1\n\n<!-- START:SPRINT-CONTEXT -->\n<!-- END:SPRINT-CONTEXT -->\n\n<!-- START:RECENT-DECISIONS -->\n<!-- END:RECENT-DECISIONS -->\n\n<!-- START:PATTERN-LIBRARY -->\n<!-- END:PATTERN-LIBRARY -->/' "$CONTEXT_FILE"
    fi
    
    # Add PRD section if missing
    if ! grep -q "<!-- START:ACTIVE-PRDS -->" "$CONTEXT_FILE"; then
        echo "Adding PRD automation section to CLAUDE.md..."
        # Add after PATTERN-LIBRARY section
        perl -i -pe 's/(<!-- END:PATTERN-LIBRARY -->)/$1\n\n<!-- START:ACTIVE-PRDS -->\n<!-- END:ACTIVE-PRDS -->/' "$CONTEXT_FILE"
    fi
}

# Generate all sections
echo "🔄 Updating CLAUDE.md..."
add_new_sections_if_missing
generate_structure
generate_violations  
generate_location
generate_sprint_context
generate_recent_decisions
generate_pattern_library
generate_active_prds

# Replace sections
replace_section "<!-- START:CURRENT-STRUCTURE -->" "<!-- END:CURRENT-STRUCTURE -->" "$TEMP_DIR/structure.txt"
replace_section "<!-- START:VIOLATIONS -->" "<!-- END:VIOLATIONS -->" "$TEMP_DIR/violations.txt"
replace_section "<!-- START:WORKING-LOCATION -->" "<!-- END:WORKING-LOCATION -->" "$TEMP_DIR/location.txt"
replace_section "<!-- START:SPRINT-CONTEXT -->" "<!-- END:SPRINT-CONTEXT -->" "$TEMP_DIR/sprint-context.txt"
replace_section "<!-- START:RECENT-DECISIONS -->" "<!-- END:RECENT-DECISIONS -->" "$TEMP_DIR/decisions.txt"
replace_section "<!-- START:PATTERN-LIBRARY -->" "<!-- END:PATTERN-LIBRARY -->" "$TEMP_DIR/patterns.txt"
replace_section "<!-- START:ACTIVE-PRDS -->" "<!-- END:ACTIVE-PRDS -->" "$TEMP_DIR/prds.txt"

# Cleanup
rm -rf "$TEMP_DIR"

echo "✅ CLAUDE.md updated successfully!"
echo ""
echo "📊 Enhanced with automated sections:"
echo "  - Sprint Context (branch, commits, focus)"
echo "  - Recent Decisions (from commits and logs)"
echo "  - Pattern Library (extracted from code)"
echo "  - Active PRDs (current sprint, vision, upcoming)"