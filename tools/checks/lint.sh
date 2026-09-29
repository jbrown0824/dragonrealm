#!/bin/zsh
# Syntax + lint check for the Roblox project, filtering noise from Roblox globals/types.
cd "${0:A:h}/../.."
fail=0
for f in $(find src -name "*.luau"); do
  err=$(luau-compile --text "$f" 2>&1 | grep -E "SyntaxError" | head -5)
  if [ -n "$err" ]; then echo "SYNTAX $f"; echo "$err"; fail=1; fi
done
GLOBALS='game|workspace|Instance|Vector3|Vector2|CFrame|Color3|ColorSequence|ColorSequenceKeypoint|NumberSequence|NumberSequenceKeypoint|NumberRange|Enum|UDim2|UDim|TweenInfo|BrickColor|Ray|RaycastParams|OverlapParams|task|tick|time|typeof|Random|Region3|PhysicalProperties|Font|DateTime|script|shared|Rect|Axes|Faces|PathWaypoint|utf8|warn|elapsedTime|settings|plugin|Path2DControlPoint'
found=$(luau-analyze $(find src -name "*.luau") 2>&1 \
  | grep -vE "Unknown global '($GLOBALS)'" \
  | grep -vE "Unknown type '(Player|Model|BasePart|Part|Folder|Instance|RemoteEvent|RemoteFunction|Humanoid|ProximityPrompt|Frame|TextLabel|TextButton|ScreenGui|GuiObject|ImageLabel|ScrollingFrame|Attachment|ParticleEmitter|Camera|Color3|Vector3|Vector2|CFrame|UDim2|BillboardGui|Sound|TweenInfo|InputObject|RaycastResult|Enum.*|Motor6D|ViewportFrame|UIStroke|TextBox|LocalScript|ModuleScript|Tween|RBXScriptConnection|Weld|WedgePart|UIListLayout)'" \
  | grep -vE "Unknown require|not found|UnknownRequire|ModuleNotFound|Cannot require|Unknown require: unsupported path" \
  | grep -vE "TypeError: Type '[^']*' could not be converted" \
  | grep -vE "Key '[A-Za-z_]+' not found in (table|class)" \
  | grep -vE "ImportUnused|FunctionUnused" \
  | grep -E "TypeError: Unknown global|LocalUnused|UnknownGlobal|ShadowGlobal|LocalShadow|DeprecatedGlobal|SameLineStatement|MultiLineStatement|UninitializedLocal|DuplicateLocal|DuplicateFunction|DuplicateCondition|UnreachableCode|UnknownType|FormatString|TableLiteral|UnbalancedAssignment|ImplicitReturn|MisleadingAndOr|IntegerParsing|ComparisonPrecedence|DuplicateKey|PlaceholderRead|IfUnnecessary|BuiltinGlobalWrite|GlobalUsedAsLocal|LocalShadowPedantic|FunctionUnused|RedundantNativeAttribute")
# anything left is a real problem (an unknown global once hid a missing forward declaration)
if [ -n "$found" ]; then echo "$found"; fail=1; fi
echo "--- done (fail=$fail)"
exit $fail
