import { LightningElement, track, api } from 'lwc';
import createWalkinLead from '@salesforce/apex/WalkinLeadController.createWalkinLead';
import LOGO from '@salesforce/resourceUrl/AU_Logo';

export default class WalkinLeadForm extends LightningElement {
  logoUrl = LOGO;

  @api formTitle = 'Masters Inquiry Form';
  @track formDate = '';
  @track firstName = '';
  @track lastName = '';
  @track email = '';
  @track mobile = '';
  @track city = '';
  @track state = '';
  @track ugDegree = '';
  @track ugUniversity = '';
  @track programValues = ''; // single select
  @track howDidYouHear = '';
  @track successMessage = null;
  @track errorMessage = null;
  @track examValues = [];  // multi select

  programOptions = [
    { label: 'Master of Business Administration', value: 'Master of Business Administration' },
    { label: 'Master of Science in Economics', value: 'Master of Science in Economics' },
    { label: 'Master of Science in Quantitative Finance', value: 'Master of Science in Quantitative Finance' },
    { label: 'Masters of Management Studies in Heritage Management', value: 'Masters of Management Studies in Heritage Management' }
  ];

  examOptions = [
    { label: 'CAT', value: 'CAT' },
    { label: 'GRE', value: 'GRE' },
    { label: 'GMAT', value: 'GMAT' },
    { label: 'CUET-PG', value: 'CUET-PG' },
    { label: 'Others', value: 'Others' }
  ];

  sourceOptions = [
    { label: 'Online Search', value: 'Online Search' },
    { label: 'Social Media', value: 'Social Media' },
    { label: 'Friends/Family', value: 'Friends/Family' },
    { label: 'My coaching institute', value: 'My coaching institute' },
    { label: 'Others', value: 'Others' }
  ];

  // computed getter for checked flags
  get examOptionsWithChecked() {
    return this.examOptions.map(exam => ({
      ...exam,
      checked: this.examValues.includes(exam.value)
    }));
  }  

  // generic input handler
  handleChange(event) {
      const id = event.target.dataset.id;
      if (id) {
          this[id] = event.target.value;

          // === Gmail Validation ===
          if (id === 'email') {
              const emailValue = event.target.value || '';
              const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

              if (!emailRegex.test(emailValue)) {
                  this.errorMessage = 'Please Use Valid Email ID';
              } else {
                  this.errorMessage = null; // clear error
              }
          }
      }
  }


  handleProgramChange(event) {
    this.programValues = event.detail.value;
  }

  handleExamsChangeCustom(event) {
    const { value, checked } = event.target;
    if (checked) {
      if (!this.examValues.includes(value)) {
        this.examValues = [...this.examValues, value];
      }
    } else {
      this.examValues = this.examValues.filter(item => item !== value);
    }
  }

  async handleSubmit() {
    this.successMessage = null;
    this.errorMessage = null;

    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

    if (!emailRegex.test(this.email)) {
        this.errorMessage = 'Use Valid Email ID';
        return;
    }    

    if (!this.firstName && !this.lastName) {
      this.errorMessage = 'Please enter your name.';
      return;
    }
    if (!this.email && !this.mobile) {
      this.errorMessage = 'Please provide Email or Mobile.';
      return;
    }

    console.log('Email entered:', this.email);
    console.log('Mobile entered:', this.mobile);
    console.log('First Name:', this.firstName);
    console.log('Last Name:', this.lastName);

    const payload = {
      formDate: this.formDate,
      firstName: this.firstName,
      lastName: this.lastName,
      email: this.email,
      mobile: this.mobile,
      city: this.city,
      state: this.state,
      company: 'Individual',
      programmesOfInterest: this.programValues, // single value
      ugDegree: this.ugDegree,
      ugUniversity: this.ugUniversity,
      entranceExams: this.examValues.join('; '),
      howDidYouHear: this.howDidYouHear
    };

    console.log('Payload sent to Apex:', JSON.stringify(payload, null, 2));

    try {
      //const leadId = await createWalkinLead({ req: payload });
      const leadId = await createWalkinLead({ reqJson: JSON.stringify(payload) });
      this.successMessage = 'Thank you! Your details have been submitted. Reference ID: ' + leadId;
      this.resetForm();
    } catch (err) {
      this.errorMessage =
        err && err.body && err.body.message
          ? err.body.message
          : 'Error submitting the form. Please try again later.';
    }
  }

  resetForm() {
    this.formDate = '';
    this.firstName = '';
    this.lastName = '';
    this.email = '';
    this.mobile = '';
    this.city = '';
    this.state = '';
    this.ugDegree = '';
    this.ugUniversity = '';
    this.programValues = '';
    this.examValues = [];
    this.howDidYouHear = '';
    this.examCheckedMap = {};
  }  

  renderedCallback() {
      const comboBoxes = this.template.querySelectorAll('lightning-combobox');
      comboBoxes.forEach(cb => {
          const input = cb.shadowRoot?.querySelector('.slds-combobox');
          if (input) {
              input.style.position = 'relative';
              input.style.zIndex = '9999';
          }
      });
  }


  handleSuccess() {
    // not used when using Apex
  }
}