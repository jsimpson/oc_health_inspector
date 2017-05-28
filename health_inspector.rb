require "erb"
require "json"
require "mechanize"
require "sequel"

RESULTS = "https://orangeeco.envisionconnect.com/api/pressAgentClient/searchFacilities?PressAgentOid=a14e5b5a-0788-490e-95b5-a70d0172bb3c"

db = Sequel.connect("sqlite://violations.db")

db.create_table?(:facilities) do
  primary_key :id
  String :facility_id
  String :facility_name
  String :address
  String :city
  String :state
  String :zip_code
end

db.create_table?(:violations) do
  primary_key :id
  foreign_key :facility_id, :facilities
  String :description
  DateTime :closure_date
  DateTime :reopen_date
end

class Facility < Sequel::Model
  plugin :validation_helpers

  one_to_many :violations

  def validate
    super
    validates_unique :facility_id
  end
end

class Violation < Sequel::Model
  plugin :validation_helpers

  many_to_one :facility

  def validate
    super
    validates_unique [:facility_id, :description, :closure_date]
  end
end

def find_facility(id)
  Facility.where(facility_id: id).any?
end

def find_violation(facility_id, description, closure_date)
  Violation.where(facility_id: facility_id, description: description, closure_date: closure_date).any?
end

def city(str)
  str.split("CA")[0].strip
end

def state
  "CA"
end

def zip_code(str)
  str.split("CA")[1].strip
end

def fetch_records(agent)
  results = agent.post(RESULTS, { "FacilityName": "Orange" }, {})

  JSON.parse(results.body).each do |result|
    unless find_facility(result["FacilityId"])
      Facility.create(
        facility_id: result["FacilityId"],
        facility_name: result["FacilityName"],
        address: result["Address"],
        city: city(result["CityStateZip"]),
        state: "CA",
        zip_code: zip_code(result["CityStateZip"])
      )
    end

    unless find_violation(result["FacilityId"], result["Violation"], result["ClosureDate"])
      begin
        reopen_date = DateTime.strptime(result["OpenDateInspector"], "%m-%d-%Y")
      rescue
        reopen_date = nil
      end

      begin
        Violation.create(
          facility_id: Facility.where(facility_id: result["FacilityId"]).first.values[:id],
          description: result["Violation"],
          closure_date: DateTime.strptime(result["ClosureDate"], "%m-%d-%Y"),
          reopen_date: reopen_date
        )
      rescue
      end
    end
  end
end

agent = Mechanize.new

fetch_records(agent)

@facilities = Facility.all

html = ERB.new(File.read("./index.erb")).result(binding)
File.open("./index.html", "w") do |file|
  file.write(html)
end

