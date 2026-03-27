import * as React from "react";
import {
  Button,
  Dialog,
  DialogActions,
  DialogBody,
  DialogContent,
  DialogSurface,
  DialogTitle,
  DialogTrigger,
  Dropdown,
  Field,
  Input,
  MessageBar,
  MessageBarBody,
  Option,
  Spinner,
  Textarea,
  makeStyles,
} from "@fluentui/react-components";
import { AddFilled } from "@fluentui/react-icons";
import type { Category, Subcategory } from "../models/Types";
import type { TicketService } from "../services/TicketService";

export interface INewTicketFormProps {
  ticketService: TicketService;
  categories: Category[];
  subcategories: Subcategory[];
  onTicketCreated: () => void;
}

const useStyles = makeStyles({
  form: {
    display: "flex",
    flexDirection: "column",
    gap: "16px",
  },
});

const urgencyOptions = [
  { value: "1", label: "1 - Critical" },
  { value: "2", label: "2 - High" },
  { value: "3", label: "3 - Medium" },
  { value: "4", label: "4 - Low" },
];

const impactOptions = [
  { value: "1", label: "1 - High (Organization)" },
  { value: "2", label: "2 - Medium (Department)" },
  { value: "3", label: "3 - Low (Individual)" },
];

/**
 * Dialog form for creating a new help desk ticket.
 * Category/Subcategory dropdowns cascade: selecting a category filters subcategories.
 */
export const NewTicketForm: React.FC<INewTicketFormProps> = ({
  ticketService,
  categories,
  subcategories,
  onTicketCreated,
}) => {
  const styles = useStyles();
  const [open, setOpen] = React.useState(false);
  const [title, setTitle] = React.useState("");
  const [description, setDescription] = React.useState("");
  const [selectedCategory, setSelectedCategory] = React.useState("");
  const [selectedSubcategory, setSelectedSubcategory] = React.useState("");
  const [urgency, setUrgency] = React.useState("3");
  const [impact, setImpact] = React.useState("3");
  const [submitting, setSubmitting] = React.useState(false);
  const [error, setError] = React.useState<string | null>(null);
  const [success, setSuccess] = React.useState(false);

  const filteredSubcategories = React.useMemo(
    () =>
      subcategories.filter(
        (sc) => sc._hd_parentcategory_value === selectedCategory
      ),
    [subcategories, selectedCategory]
  );

  const resetForm = (): void => {
    setTitle("");
    setDescription("");
    setSelectedCategory("");
    setSelectedSubcategory("");
    setUrgency("3");
    setImpact("3");
    setError(null);
    setSuccess(false);
  };

  const handleSubmit = async (): Promise<void> => {
    if (!title.trim() || !description.trim()) {
      setError("Title and description are required.");
      return;
    }

    setSubmitting(true);
    setError(null);

    try {
      const ticketPayload: {
        hd_title: string;
        hd_description: string;
        "hd_category@odata.bind": string;
        "hd_subcategory@odata.bind"?: string;
        hd_urgency: number;
        hd_impact: number;
      } = {
        hd_title: title.trim(),
        hd_description: description.trim(),
        "hd_category@odata.bind": selectedCategory
          ? `/hd_categories(${selectedCategory})`
          : "",
        hd_urgency: parseInt(urgency, 10),
        hd_impact: parseInt(impact, 10),
      };

      if (selectedSubcategory) {
        ticketPayload["hd_subcategory@odata.bind"] =
          `/hd_subcategories(${selectedSubcategory})`;
      }

      await ticketService.createTicket(ticketPayload);
      setSuccess(true);
      onTicketCreated();

      // Auto-close after success
      setTimeout(() => {
        setOpen(false);
        resetForm();
      }, 1500);
    } catch (err) {
      setError(
        err instanceof Error ? err.message : "Failed to create ticket."
      );
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <Dialog
      open={open}
      onOpenChange={(_e, data) => {
        setOpen(data.open);
        if (!data.open) resetForm();
      }}
    >
      <DialogTrigger disableButtonEnhancement>
        <Button appearance="primary" icon={<AddFilled />}>
          New Ticket
        </Button>
      </DialogTrigger>

      <DialogSurface>
        <DialogBody>
          <DialogTitle>Create New Ticket</DialogTitle>
          <DialogContent>
            <div className={styles.form}>
              {error && (
                <MessageBar intent="error">
                  <MessageBarBody>{error}</MessageBarBody>
                </MessageBar>
              )}
              {success && (
                <MessageBar intent="success">
                  <MessageBarBody>
                    Ticket created successfully!
                  </MessageBarBody>
                </MessageBar>
              )}

              <Field label="Title" required>
                <Input
                  value={title}
                  onChange={(_e, data) => setTitle(data.value)}
                  placeholder="Brief summary of your issue"
                  disabled={submitting}
                />
              </Field>

              <Field label="Description" required>
                <Textarea
                  value={description}
                  onChange={(_e, data) => setDescription(data.value)}
                  placeholder="Describe your issue in detail..."
                  resize="vertical"
                  rows={4}
                  disabled={submitting}
                />
              </Field>

              <Field label="Category">
                <Dropdown
                  placeholder="Select a category"
                  value={
                    categories.find((c) => c.hd_categoryid === selectedCategory)
                      ?.hd_name || ""
                  }
                  onOptionSelect={(_e, data) => {
                    setSelectedCategory(data.optionValue || "");
                    setSelectedSubcategory("");
                  }}
                  disabled={submitting}
                >
                  {categories.map((cat) => (
                    <Option
                      key={cat.hd_categoryid}
                      value={cat.hd_categoryid}
                      text={cat.hd_name}
                    >
                      {cat.hd_name}
                    </Option>
                  ))}
                </Dropdown>
              </Field>

              <Field label="Subcategory">
                <Dropdown
                  placeholder={
                    selectedCategory
                      ? "Select a subcategory"
                      : "Select a category first"
                  }
                  value={
                    filteredSubcategories.find(
                      (sc) => sc.hd_subcategoryid === selectedSubcategory
                    )?.hd_name || ""
                  }
                  onOptionSelect={(_e, data) =>
                    setSelectedSubcategory(data.optionValue || "")
                  }
                  disabled={!selectedCategory || submitting}
                >
                  {filteredSubcategories.map((sc) => (
                    <Option
                      key={sc.hd_subcategoryid}
                      value={sc.hd_subcategoryid}
                      text={sc.hd_name}
                    >
                      {sc.hd_name}
                    </Option>
                  ))}
                </Dropdown>
              </Field>

              <Field label="Urgency">
                <Dropdown
                  value={
                    urgencyOptions.find((o) => o.value === urgency)?.label || ""
                  }
                  onOptionSelect={(_e, data) =>
                    setUrgency(data.optionValue || "3")
                  }
                  disabled={submitting}
                >
                  {urgencyOptions.map((opt) => (
                    <Option key={opt.value} value={opt.value} text={opt.label}>
                      {opt.label}
                    </Option>
                  ))}
                </Dropdown>
              </Field>

              <Field label="Impact">
                <Dropdown
                  value={
                    impactOptions.find((o) => o.value === impact)?.label || ""
                  }
                  onOptionSelect={(_e, data) =>
                    setImpact(data.optionValue || "3")
                  }
                  disabled={submitting}
                >
                  {impactOptions.map((opt) => (
                    <Option key={opt.value} value={opt.value} text={opt.label}>
                      {opt.label}
                    </Option>
                  ))}
                </Dropdown>
              </Field>
            </div>
          </DialogContent>
          <DialogActions>
            <DialogTrigger disableButtonEnhancement>
              <Button appearance="secondary" disabled={submitting}>
                Cancel
              </Button>
            </DialogTrigger>
            <Button
              appearance="primary"
              onClick={handleSubmit}
              disabled={submitting || success}
            >
              {submitting ? (
                <Spinner size="tiny" label="Creating..." />
              ) : (
                "Submit Ticket"
              )}
            </Button>
          </DialogActions>
        </DialogBody>
      </DialogSurface>
    </Dialog>
  );
};
