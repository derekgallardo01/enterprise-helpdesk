import * as React from 'react';

// Since we can't easily render Fluent UI in Jest without full provider setup,
// we test the component logic by importing the status map and verifying mappings.
import { StatusMap, PriorityMap } from '../../models/Types';

describe('StatusMap', () => {
  it('should map all 8 status values', () => {
    expect(Object.keys(StatusMap)).toHaveLength(8);
  });

  it('should map status 1 to New', () => {
    expect(StatusMap[1]).toBe('New');
  });

  it('should map status 2 to Assigned', () => {
    expect(StatusMap[2]).toBe('Assigned');
  });

  it('should map status 3 to In Progress', () => {
    expect(StatusMap[3]).toBe('In Progress');
  });

  it('should map status 4 to Waiting on Customer', () => {
    expect(StatusMap[4]).toBe('Waiting on Customer');
  });

  it('should map status 5 to Waiting on Third Party', () => {
    expect(StatusMap[5]).toBe('Waiting on Third Party');
  });

  it('should map status 6 to Resolved', () => {
    expect(StatusMap[6]).toBe('Resolved');
  });

  it('should map status 7 to Closed', () => {
    expect(StatusMap[7]).toBe('Closed');
  });

  it('should map status 8 to Cancelled', () => {
    expect(StatusMap[8]).toBe('Cancelled');
  });
});

describe('PriorityMap', () => {
  it('should map all 4 priority values', () => {
    expect(Object.keys(PriorityMap)).toHaveLength(4);
  });

  it('should map priority 1 to Critical', () => {
    expect(PriorityMap[1]).toBe('Critical');
  });

  it('should map priority 2 to High', () => {
    expect(PriorityMap[2]).toBe('High');
  });

  it('should map priority 3 to Medium', () => {
    expect(PriorityMap[3]).toBe('Medium');
  });

  it('should map priority 4 to Low', () => {
    expect(PriorityMap[4]).toBe('Low');
  });
});
