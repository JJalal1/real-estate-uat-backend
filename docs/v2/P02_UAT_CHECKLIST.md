# V2 P02 — Team UAT checklist

Test this build as a normal user. P02 is cumulative: first confirm P01 still works, then focus on discovery.

## Guest discovery

- Open the app without logging in.
- Confirm the home immediately makes it clear how to find a property.
- Open the marketplace.
- Move and zoom the map.
- Switch between map and list.
- Search by area/address words.
- Test sale and rent.
- Test each property type.
- Test price, currency, rooms, bathrooms, and area filters.
- Draw/select a map area and confirm results stay within it.
- Open several property detail screens.
- Check loading, empty, offline/error, and retry behavior.

## Currency and area

- Confirm price denomination is visible and never silently converted.
- Test northern YER denomination, southern YER denomination, SAR, and USD where data exists.
- Confirm listings with local area units show their original unit.
- Create a request using a local area unit and confirm it remains in that unit.

## Favorites and private property requests

- While logged out, try to save a favorite and confirm the login flow is understandable.
- Log in and save/remove favorites.
- Open Favorites from Home and Account.
- Search for something unavailable and create a private property request.
- Confirm the request explains that it is not visible to dalals/offices.
- Open, edit, disable notifications for, and delete a private request.
- Confirm matching count behaves consistently with the selected filters.

## Feedback format

For each note send:
- Screen/flow.
- What you tried.
- What happened.
- What you expected.
- Severity: blocking / important / improvement.
- Screenshot for visual issues.

P02 is not closed until blocking notes are resolved and the product owner accepts it.
