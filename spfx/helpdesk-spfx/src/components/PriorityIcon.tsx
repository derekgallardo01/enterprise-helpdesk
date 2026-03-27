import * as React from "react";
import {
  ArrowUpFilled,
  SubtractFilled,
  ArrowDownFilled,
} from "@fluentui/react-icons";
import { tokens, Text } from "@fluentui/react-components";
import { PriorityMap } from "../models/Types";

export interface IPriorityIconProps {
  priority: number;
  showLabel?: boolean;
}

interface PriorityConfig {
  icon: React.ReactElement;
  color: string;
}

const priorityConfigMap: Record<number, PriorityConfig> = {
  1: {
    icon: <ArrowUpFilled />,
    color: tokens.colorPaletteRedForeground1,
  },
  2: {
    icon: <ArrowUpFilled />,
    color: tokens.colorPaletteDarkOrangeForeground1,
  },
  3: {
    icon: <SubtractFilled />,
    color: tokens.colorPaletteBlueForeground2,
  },
  4: {
    icon: <ArrowDownFilled />,
    color: tokens.colorNeutralForeground3,
  },
};

/**
 * Renders a priority icon with semantic color and optional text label.
 */
export const PriorityIcon: React.FC<IPriorityIconProps> = ({
  priority,
  showLabel = true,
}) => {
  const config = priorityConfigMap[priority] || priorityConfigMap[3];
  const label = PriorityMap[priority] || `Unknown (${priority})`;

  return (
    <span
      style={{
        display: "inline-flex",
        alignItems: "center",
        gap: "4px",
        color: config.color,
      }}
    >
      {config.icon}
      {showLabel && (
        <Text size={200} style={{ color: config.color }}>
          {label}
        </Text>
      )}
    </span>
  );
};
