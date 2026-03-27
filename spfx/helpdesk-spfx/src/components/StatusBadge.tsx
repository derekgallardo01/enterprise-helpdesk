import * as React from "react";
import {
  Badge,
  type BadgeProps,
} from "@fluentui/react-components";
import { StatusMap } from "../models/Types";

export interface IStatusBadgeProps {
  status: number;
}

/**
 * Maps a Dataverse ticket status integer to a semantically colored Fluent UI v9 Badge.
 */
const statusColorMap: Record<number, BadgeProps["color"]> = {
  1: "informative", // New
  2: "brand",       // Assigned
  3: "warning",     // In Progress
  4: "warning",     // Waiting on Customer
  5: "warning",     // Waiting on Third Party
  6: "success",     // Resolved
  7: "subtle",      // Closed
  8: "danger",      // Cancelled
};

export const StatusBadge: React.FC<IStatusBadgeProps> = ({ status }) => {
  const label = StatusMap[status] || `Unknown (${status})`;
  const color = statusColorMap[status] || "informative";

  return (
    <Badge
      appearance="filled"
      color={color}
      size="medium"
    >
      {label}
    </Badge>
  );
};
